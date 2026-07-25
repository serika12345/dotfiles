import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';
import {Keyboard} from 'resource:///org/gnome/shell/ui/keyboard.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';

// This is tall enough for GNOME's candidate buttons at the configured 2x
// display scale, while remaining constant when the row is empty.
const SUGGESTIONS_HEIGHT = 60;

export default class FixedOskSuggestionsHeightExtension extends Extension {
    enable() {
        this._injectionManager = new InjectionManager();

        const fixSuggestionsHeight = keyboard => {
            if (keyboard?._suggestions)
                keyboard._suggestions.height = SUGGESTIONS_HEIGHT;
        };

        // The accessibility setting creates the keyboard before extensions are
        // loaded, so also update the already existing instance.
        fixSuggestionsHeight(Main.keyboard.keyboardActor);

        // Retain the fix if GNOME recreates the keyboard later.
        this._injectionManager.overrideMethod(
            Keyboard.prototype,
            '_init',
            originalMethod => function (...args) {
                originalMethod.call(this, ...args);
                fixSuggestionsHeight(this);
            });
    }

    disable() {
        this._injectionManager.clear();
        this._injectionManager = null;

        // -1 restores Clutter's natural-height calculation.
        Main.keyboard.keyboardActor?._suggestions?.set_height(-1);
    }
}
