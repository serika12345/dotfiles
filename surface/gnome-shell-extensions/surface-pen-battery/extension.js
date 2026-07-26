import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const UPOWER_NAME = 'org.freedesktop.UPower';
const UPOWER_PATH = '/org/freedesktop/UPower';
const SURFACE_PEN_MODEL = 'surface pen';
const REFRESH_INTERVAL_SECONDS = 60;

const UPowerProxy = Gio.DBusProxy.makeProxyWrapper(`
<node>
  <interface name="org.freedesktop.UPower">
    <method name="EnumerateDevices">
      <arg type="ao" name="devices" direction="out"/>
    </method>
    <signal name="DeviceAdded">
      <arg type="o" name="device"/>
    </signal>
    <signal name="DeviceRemoved">
      <arg type="o" name="device"/>
    </signal>
  </interface>
</node>`);

const UPowerDeviceProxy = Gio.DBusProxy.makeProxyWrapper(`
<node>
  <interface name="org.freedesktop.UPower.Device">
    <method name="Refresh"/>
    <property name="NativePath" type="s" access="read"/>
    <property name="Model" type="s" access="read"/>
    <property name="Serial" type="s" access="read"/>
    <property name="UpdateTime" type="t" access="read"/>
    <property name="Percentage" type="d" access="read"/>
    <property name="IsPresent" type="b" access="read"/>
  </interface>
</node>`);

function batteryIconName(percentage) {
    if (percentage <= 5)
        return 'battery-empty-symbolic';
    if (percentage <= 20)
        return 'battery-caution-symbolic';
    if (percentage <= 40)
        return 'battery-low-symbolic';
    if (percentage <= 80)
        return 'battery-good-symbolic';

    return 'battery-full-symbolic';
}

function isSurfacePen(proxy) {
    const model = String(proxy.Model ?? '').toLowerCase();
    return model.includes(SURFACE_PEN_MODEL);
}

function formatUpdateTime(updateTime) {
    const timestamp = Number(updateTime);
    if (!timestamp)
        return 'Last update: unknown';

    const date = GLib.DateTime.new_from_unix_local(timestamp);
    return `Last update: ${date.format('%Y-%m-%d %H:%M:%S')}`;
}

const SurfacePenBatteryIndicator = GObject.registerClass(
class SurfacePenBatteryIndicator extends PanelMenu.Button {
    _init() {
        super._init(0.0, 'Surface Pen Battery');

        this._box = new St.BoxLayout({
            style_class: 'panel-status-menu-box',
        });
        this._icon = new St.Icon({
            icon_name: 'input-tablet-symbolic',
            style_class: 'system-status-icon',
        });
        this._label = new St.Label({
            text: 'Pen --',
            y_align: Clutter.ActorAlign.CENTER,
            style: 'min-width: 4.8em;',
        });

        this._box.add_child(this._icon);
        this._box.add_child(this._label);
        this.add_child(this._box);

        this._summaryItem = new PopupMenu.PopupMenuItem(
            'Surface Pen: not connected',
            {reactive: false});
        this._updatedItem = new PopupMenu.PopupMenuItem(
            'Last update: unknown',
            {reactive: false});

        this.menu.addMenuItem(this._summaryItem);
        this.menu.addMenuItem(this._updatedItem);
    }

    setUnavailable(message) {
        this._icon.icon_name = 'input-tablet-symbolic';
        this._icon.opacity = 170;
        this._label.opacity = 170;
        this._label.text = 'Pen --';
        this._summaryItem.label.text = `Surface Pen: ${message}`;
        this._updatedItem.label.text = 'Last update: unknown';
    }

    setBattery(percentage, updateTime, serial, stale = false) {
        const rounded = Math.round(percentage);
        const opacity = stale ? 170 : 255;

        this._icon.icon_name = batteryIconName(rounded);
        this._icon.opacity = opacity;
        this._label.opacity = opacity;
        this._label.text = `Pen ${rounded}%`;

        let summary = `Surface Pen: ${rounded}%`;
        if (stale)
            summary += ' (last known)';
        else if (serial)
            summary += ` (${serial})`;

        this._summaryItem.label.text = summary;
        this._updatedItem.label.text = formatUpdateTime(updateTime);
    }
});

export default class SurfacePenBatteryExtension extends Extension {
    enable() {
        this._enabled = true;
        this._scanGeneration = 0;
        this._lastPercentage = null;
        this._lastSerial = null;
        this._lastUpdateTime = null;

        this._indicator = new SurfacePenBatteryIndicator();
        this._indicator.setUnavailable('not connected');
        Main.panel.addToStatusArea(this.uuid, this._indicator, 0, 'right');

        this._initUPower();
        this._refreshTimeoutId = GLib.timeout_add_seconds(
            GLib.PRIORITY_DEFAULT,
            REFRESH_INTERVAL_SECONDS,
            () => {
                this._refresh();
                return GLib.SOURCE_CONTINUE;
            });
    }

    disable() {
        this._enabled = false;

        if (this._refreshTimeoutId) {
            GLib.Source.remove(this._refreshTimeoutId);
            this._refreshTimeoutId = 0;
        }

        this._disconnectUPower();
        this._disconnectDevice();
        this._indicator?.destroy();
        this._indicator = null;
    }

    _initUPower() {
        this._upowerProxy = new UPowerProxy(
            Gio.DBus.system,
            UPOWER_NAME,
            UPOWER_PATH,
            (proxy, error) => {
                if (!this._enabled)
                    return;

                if (error) {
                    logError(error, 'Failed to connect to UPower');
                    this._indicator.setUnavailable('UPower unavailable');
                    return;
                }

                this._deviceAddedSignalId = proxy.connectSignal(
                    'DeviceAdded',
                    (_proxy, _sender, [path]) => this._inspectDevice(path));
                this._deviceRemovedSignalId = proxy.connectSignal(
                    'DeviceRemoved',
                    (_proxy, _sender, [path]) => this._handleDeviceRemoved(path));

                this._findPen();
            });
    }

    _disconnectUPower() {
        if (!this._upowerProxy)
            return;

        if (this._deviceAddedSignalId)
            this._upowerProxy.disconnectSignal(this._deviceAddedSignalId);
        if (this._deviceRemovedSignalId)
            this._upowerProxy.disconnectSignal(this._deviceRemovedSignalId);

        this._deviceAddedSignalId = 0;
        this._deviceRemovedSignalId = 0;
        this._upowerProxy = null;
    }

    _findPen() {
        if (!this._upowerProxy)
            return;

        const generation = ++this._scanGeneration;
        this._upowerProxy.EnumerateDevicesRemote((result, error) => {
            if (!this._enabled || generation !== this._scanGeneration)
                return;

            if (error) {
                logError(error, 'Failed to enumerate UPower devices');
                this._indicator.setUnavailable('UPower error');
                return;
            }

            const [paths] = result;
            this._inspectDeviceList(paths, generation);
        });
    }

    _inspectDeviceList(paths, generation) {
        if (paths.length === 0) {
            this._disconnectDevice();
            this._showDisconnected();
            return;
        }

        let remaining = paths.length;
        let found = false;

        for (const path of paths) {
            this._createDeviceProxy(path, (proxy, error) => {
                if (!this._enabled || generation !== this._scanGeneration || found)
                    return;

                remaining--;

                if (!error && isSurfacePen(proxy)) {
                    found = true;
                    this._setDevice(path, proxy);
                    return;
                }

                if (remaining === 0) {
                    this._disconnectDevice();
                    this._showDisconnected();
                }
            });
        }
    }

    _inspectDevice(path) {
        this._createDeviceProxy(path, (proxy, error) => {
            if (!this._enabled || error || !isSurfacePen(proxy))
                return;

            this._setDevice(path, proxy);
        });
    }

    _createDeviceProxy(path, callback) {
        new UPowerDeviceProxy(
            Gio.DBus.system,
            UPOWER_NAME,
            path,
            callback);
    }

    _setDevice(path, proxy) {
        this._disconnectDevice();

        this._devicePath = path;
        this._deviceProxy = proxy;
        this._devicePropertiesSignalId = proxy.connect(
            'g-properties-changed',
            () => this._updateFromDevice());

        this._updateFromDevice();
    }

    _disconnectDevice() {
        if (this._deviceProxy && this._devicePropertiesSignalId)
            this._deviceProxy.disconnect(this._devicePropertiesSignalId);

        this._devicePath = null;
        this._deviceProxy = null;
        this._devicePropertiesSignalId = 0;
    }

    _handleDeviceRemoved(path) {
        if (this._devicePath !== path)
            return;

        this._disconnectDevice();
        this._showDisconnected();
        this._findPen();
    }

    _refresh() {
        if (this._deviceProxy) {
            this._deviceProxy.RefreshRemote(() => this._updateFromDevice());
            return;
        }

        this._findPen();
    }

    _updateFromDevice() {
        if (!this._deviceProxy)
            return;

        const percentage = Number(this._deviceProxy.Percentage);
        if (!Number.isFinite(percentage)) {
            this._showDisconnected('battery unknown');
            return;
        }

        this._lastPercentage = percentage;
        this._lastUpdateTime = this._deviceProxy.UpdateTime;
        this._lastSerial = this._deviceProxy.Serial;
        this._indicator.setBattery(
            percentage,
            this._lastUpdateTime,
            this._lastSerial);
    }

    _showDisconnected(message = 'not connected') {
        if (this._lastPercentage === null) {
            this._indicator.setUnavailable(message);
            return;
        }

        this._indicator.setBattery(
            this._lastPercentage,
            this._lastUpdateTime,
            this._lastSerial,
            true);
    }
}
