#include "calibration.h"

#include <QApplication>
#include <QCommandLineParser>
#include <QCursor>
#include <QDir>
#include <QFile>
#include <QFont>
#include <QKeyEvent>
#include <QMessageBox>
#include <QMouseEvent>
#include <QPainter>
#include <QProcess>
#include <QSaveFile>
#include <QScreen>
#include <QSocketNotifier>
#include <QStandardPaths>
#include <QTabletEvent>
#include <QTextStream>
#include <QTimer>
#include <QWidget>

#include <array>
#include <cerrno>
#include <cmath>
#include <cstring>
#include <fcntl.h>
#include <linux/input.h>
#include <memory>
#include <optional>
#include <sys/ioctl.h>
#include <unistd.h>
#include <vector>

#ifndef INSTALL_HELPER_PATH
#define INSTALL_HELPER_PATH "surface-pen-calibration-install"
#endif

#ifndef PKEXEC_PATH
#define PKEXEC_PATH "pkexec"
#endif

namespace {

constexpr auto stylus_device_name =
  "IPTSD Virtual Stylus 045E:099F";

constexpr std::array targets {
  calibration::Point {0.10, 0.10},
  calibration::Point {0.90, 0.10},
  calibration::Point {0.90, 0.90},
  calibration::Point {0.10, 0.90},
  calibration::Point {0.50, 0.50},
  calibration::Point {0.50, 0.10},
  calibration::Point {0.90, 0.50},
  calibration::Point {0.50, 0.90},
  calibration::Point {0.10, 0.50},
};

QString matrix_text(const calibration::Matrix &matrix)
{
  QStringList values;
  for (const double value : matrix.values()) {
    values.append(QString::number(value, 'g', 12));
  }
  return values.join(u' ');
}

class CalibrationWindow final : public QWidget {
public:
  explicit CalibrationWindow(const bool allow_mouse)
    : m_allow_mouse(allow_mouse)
  {
    setWindowTitle(tr("Surface Pen Calibration"));
    setAttribute(Qt::WA_AcceptTouchEvents, false);
    setFocusPolicy(Qt::StrongFocus);
    setCursor(Qt::BlankCursor);
    setAutoFillBackground(false);

    connect(&m_installer,
            &QProcess::finished,
            this,
            [this](const int exit_code,
                   const QProcess::ExitStatus exit_status) {
              if (exit_status == QProcess::NormalExit && exit_code == 0) {
                m_phase = Phase::Applied;
                if (m_resetting) {
                  m_message =
                    tr("保存済みの補正を削除し、単位行列へ戻しました。");
                } else {
                  m_message =
                    tr("補正を適用しました。ペンを画面上で動かして確認してください。");
                }
              } else {
                m_phase = Phase::Error;
                const QString details =
                  QString::fromUtf8(m_installer.readAllStandardError())
                    .trimmed();
                m_message =
                  tr("補正の適用に失敗しました。%1")
                    .arg(details.isEmpty()
                           ? tr("Polkit認証またはIPTSDの再起動を確認してください。")
                           : details);
              }
              m_resetting = false;
              update();
            });
    connect(&m_installer,
            &QProcess::errorOccurred,
            this,
            [this](const QProcess::ProcessError error) {
              if (error != QProcess::FailedToStart) {
                return;
              }
              m_phase = Phase::Error;
              m_message =
                tr("管理者認証を開始できませんでした: %1")
                  .arg(m_installer.errorString());
              m_resetting = false;
              update();
            });

    if (!open_stylus()) {
      m_phase = Phase::Error;
      m_message =
        tr("IPTSD仮想スタイラスを開けませんでした。\n%1")
          .arg(m_device_error);
    }
  }

  ~CalibrationWindow() override
  {
    if (m_stylus_fd >= 0) {
      ::close(m_stylus_fd);
    }
  }

protected:
  void paintEvent(QPaintEvent *) override
  {
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.fillRect(rect(), QColor(13, 17, 23));

    if (m_phase == Phase::Calibrating) {
      paint_calibration(painter);
    } else {
      paint_result(painter);
    }
  }

  void tabletEvent(QTabletEvent *event) override
  {
    // Calibration reads the IPTSD evdev device directly. Accepting tablet
    // events here prevents Qt from synthesizing duplicate mouse presses.
    event->accept();
  }

  void mousePressEvent(QMouseEvent *event) override
  {
    if (!m_allow_mouse) {
      return;
    }

    if (m_phase == Phase::Complete ||
        m_phase == Phase::Error) {
      apply();
      return;
    }

    if (m_phase == Phase::Calibrating) {
      add_measurement(event->position());
    }
  }

  void keyPressEvent(QKeyEvent *event) override
  {
    switch (event->key()) {
    case Qt::Key_Escape:
      close();
      break;
    case Qt::Key_Backspace:
      if (m_phase == Phase::Calibrating && !m_measured.empty()) {
        m_measured.pop_back();
        update();
      }
      break;
    case Qt::Key_R:
      restart();
      break;
    case Qt::Key_D:
      reset_calibration();
      break;
    case Qt::Key_Return:
    case Qt::Key_Enter:
      apply();
      break;
    default:
      QWidget::keyPressEvent(event);
      break;
    }
  }

private:
  enum class Phase {
    Calibrating,
    Complete,
    Applying,
    Applied,
    Error,
  };

  static QPointF to_widget(const calibration::Point point,
                           const QSize size)
  {
    return {
      point.x * static_cast<double>(size.width()),
      point.y * static_cast<double>(size.height()),
    };
  }

  bool open_stylus()
  {
    const QStringList events =
      QDir(QStringLiteral("/dev/input"))
        .entryList({QStringLiteral("event*")},
                   QDir::System | QDir::Files,
                   QDir::Name);
    bool permission_denied = false;

    for (const QString &entry : events) {
      const QString path = QStringLiteral("/dev/input/") + entry;
      const QByteArray encoded_path = QFile::encodeName(path);
      const int descriptor =
        ::open(encoded_path.constData(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
      if (descriptor < 0) {
        permission_denied = permission_denied || errno == EACCES;
        continue;
      }

      std::array<char, 256> name {};
      if (::ioctl(descriptor,
                  EVIOCGNAME(static_cast<int>(name.size())),
                  name.data()) < 0 ||
          QString::fromLocal8Bit(name.data()) !=
            QString::fromUtf8(stylus_device_name)) {
        ::close(descriptor);
        continue;
      }

      input_absinfo horizontal {};
      input_absinfo vertical {};
      if (::ioctl(descriptor, EVIOCGABS(ABS_X), &horizontal) < 0 ||
          ::ioctl(descriptor, EVIOCGABS(ABS_Y), &vertical) < 0 ||
          horizontal.maximum <= horizontal.minimum ||
          vertical.maximum <= vertical.minimum) {
        m_device_error =
          tr("%1の座標範囲を取得できません: %2")
            .arg(path, QString::fromLocal8Bit(std::strerror(errno)));
        ::close(descriptor);
        return false;
      }

      m_stylus_fd = descriptor;
      m_raw_x = horizontal.value;
      m_raw_y = vertical.value;
      m_x_min = horizontal.minimum;
      m_x_max = horizontal.maximum;
      m_y_min = vertical.minimum;
      m_y_max = vertical.maximum;
      m_stylus_notifier =
        std::make_unique<QSocketNotifier>(m_stylus_fd,
                                          QSocketNotifier::Read,
                                          this);
      connect(m_stylus_notifier.get(),
              &QSocketNotifier::activated,
              this,
              [this] { read_stylus_events(); });
      return true;
    }

    m_device_error =
      permission_denied
        ? tr("入力デバイスの読み取り権限がありません。"
             "NixOS構成を反映してログインし直してください。")
        : tr("%1が見つかりません。IPTSDの状態を確認してください。")
            .arg(QString::fromUtf8(stylus_device_name));
    return false;
  }

  void read_stylus_events()
  {
    std::array<input_event, 32> events {};

    while (true) {
      const ssize_t bytes =
        ::read(m_stylus_fd, events.data(), sizeof(events));
      if (bytes < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
          return;
        }
        m_stylus_notifier->setEnabled(false);
        m_phase = Phase::Error;
        m_message =
          tr("スタイラス入力の読み取りに失敗しました: %1")
            .arg(QString::fromLocal8Bit(std::strerror(errno)));
        update();
        return;
      }
      if (bytes == 0) {
        return;
      }

      const std::size_t count =
        static_cast<std::size_t>(bytes) / sizeof(input_event);
      for (std::size_t index = 0; index < count; ++index) {
        const input_event &event = events[index];
        if (event.type == EV_ABS && event.code == ABS_X) {
          m_raw_x = event.value;
        } else if (event.type == EV_ABS && event.code == ABS_Y) {
          m_raw_y = event.value;
        } else if (event.type == EV_KEY &&
                   event.code == BTN_TOUCH &&
                   event.value == 1) {
          m_pending_tip_down = true;
        } else if (event.type == EV_SYN &&
                   event.code == SYN_DROPPED) {
          m_pending_tip_down = false;
        } else if (event.type == EV_SYN &&
                   event.code == SYN_REPORT &&
                   m_pending_tip_down) {
          m_pending_tip_down = false;
          handle_raw_tip_down();
        }
      }
    }
  }

  void handle_raw_tip_down()
  {
    if (m_phase == Phase::Calibrating) {
      const double normalized_x =
        static_cast<double>(m_raw_x - m_x_min) /
        static_cast<double>(m_x_max - m_x_min);
      const double normalized_y =
        static_cast<double>(m_raw_y - m_y_min) /
        static_cast<double>(m_y_max - m_y_min);
      add_measurement(
        {normalized_x * static_cast<double>(width()),
         normalized_y * static_cast<double>(height())});
    } else if (m_phase == Phase::Complete ||
               (m_phase == Phase::Error && m_result.has_value())) {
      apply();
    }
  }

  void paint_calibration(QPainter &painter)
  {
    const auto target = to_widget(targets[m_measured.size()], size());

    QPen outer_pen(QColor(246, 248, 250), 5.0);
    painter.setPen(outer_pen);
    painter.setBrush(Qt::NoBrush);
    painter.drawEllipse(target, 34.0, 34.0);

    painter.setPen(QPen(QColor(68, 147, 248), 5.0));
    painter.drawEllipse(target, 15.0, 15.0);
    painter.drawLine(target + QPointF(-48.0, 0.0),
                     target + QPointF(48.0, 0.0));
    painter.drawLine(target + QPointF(0.0, -48.0),
                     target + QPointF(0.0, 48.0));

    painter.setPen(QColor(246, 248, 250));
    QFont title_font = font();
    title_font.setPointSize(20);
    title_font.setBold(true);
    painter.setFont(title_font);
    painter.drawText(
      QRectF(0.0, 28.0, width(), 44.0),
      Qt::AlignHCenter | Qt::AlignTop,
      tr("Surface Penでターゲットの中心をタップしてください"));

    QFont body_font = font();
    body_font.setPointSize(12);
    painter.setFont(body_font);
    painter.setPen(QColor(180, 188, 198));
    painter.drawText(
      QRectF(0.0, 78.0, width(), 32.0),
      Qt::AlignHCenter | Qt::AlignTop,
      tr("%1 / %2点  ·  Backspace: 1点戻る  ·  R: 最初から  ·  Esc: 終了")
        .arg(m_measured.size() + 1)
        .arg(targets.size()));
  }

  void paint_result(QPainter &painter)
  {
    painter.setPen(QColor(246, 248, 250));
    QFont title_font = font();
    title_font.setPointSize(24);
    title_font.setBold(true);
    painter.setFont(title_font);

    QString title;
    switch (m_phase) {
    case Phase::Complete:
      title = tr("測定が完了しました");
      break;
    case Phase::Applying:
      title = tr("補正を適用しています…");
      break;
    case Phase::Applied:
      title = tr("補正を適用しました");
      break;
    case Phase::Error:
      title = tr("エラー");
      break;
    case Phase::Calibrating:
      break;
    }
    painter.drawText(
      QRectF(80.0, height() * 0.18, width() - 160.0, 60.0),
      Qt::AlignCenter,
      title);

    QFont body_font = font();
    body_font.setPointSize(13);
    painter.setFont(body_font);
    painter.setPen(QColor(190, 198, 208));

    QString details = m_message;
    if (m_result.has_value()) {
      details +=
        tr("\n\nRMS誤差: %1 px   最大誤差: %2 px"
           "\n\nlibinput行列:\n%3")
          .arg(m_result->rms_error * std::hypot(width(), height()),
               0,
               'f',
               2)
          .arg(m_result->maximum_error * std::hypot(width(), height()),
               0,
               'f',
               2)
          .arg(matrix_text(m_final_matrix));
    }

    painter.drawText(
      QRectF(100.0, height() * 0.30, width() - 200.0, height() * 0.35),
      Qt::AlignHCenter | Qt::AlignTop | Qt::TextWordWrap,
      details);

    painter.setPen(QColor(68, 147, 248));
    QFont action_font = font();
    action_font.setPointSize(15);
    action_font.setBold(true);
    painter.setFont(action_font);

    QString action;
    if (m_phase == Phase::Complete) {
      action = tr("画面をタップまたはEnterで適用（管理者認証）");
    } else if (m_phase == Phase::Applying) {
      action = tr("認証ダイアログを完了してください");
    } else if (m_phase == Phase::Applied) {
      action = tr("R: 再測定  ·  D: 補正を初期化  ·  Esc: 終了");
    } else if (m_result.has_value()) {
      action =
        tr("画面をタップまたはEnterで再適用  ·  R: 再測定  ·  D: 初期化");
    } else {
      action = tr("R: 再測定  ·  D: 補正を初期化  ·  Esc: 終了");
    }
    painter.drawText(
      QRectF(80.0, height() * 0.75, width() - 160.0, 50.0),
      Qt::AlignCenter,
      action);
  }

  void add_measurement(const QPointF position)
  {
    if (width() <= 0 || height() <= 0 ||
        m_measured.size() >= targets.size()) {
      return;
    }

    m_measured.push_back({
      .x = position.x() / static_cast<double>(width()),
      .y = position.y() / static_cast<double>(height()),
    });

    if (m_measured.size() == targets.size()) {
      try {
        m_result = calibration::fit_affine(m_measured, targets);
        m_final_matrix = m_result->matrix;
        m_phase = Phase::Complete;
        m_message =
          tr("算出した補正をIPTSD仮想スタイラスへ適用できます。"
             "\n適用時にIPTSDが再起動し、ペン入力が一度切断されます。");
        save_user_copy();
      } catch (const std::exception &error) {
        m_phase = Phase::Error;
        m_message =
          tr("行列を計算できませんでした: %1")
            .arg(QString::fromUtf8(error.what()));
      }
    }
    update();
  }

  void save_user_copy() const
  {
    const QString directory =
      QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) +
      QStringLiteral("/surface-pen-calibration");
    if (!QDir().mkpath(directory)) {
      return;
    }

    QSaveFile file(directory + QStringLiteral("/last-matrix"));
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
      return;
    }
    file.write(matrix_text(m_final_matrix).toUtf8());
    file.write("\n");
    file.commit();
  }

  void apply()
  {
    if (m_phase == Phase::Applying || !m_result.has_value()) {
      return;
    }

    QStringList arguments {
      QString::fromUtf8(INSTALL_HELPER_PATH),
    };
    for (const double value : m_final_matrix.values()) {
      arguments.append(QString::number(value, 'g', 12));
    }

    m_phase = Phase::Applying;
    m_message = tr("Polkitで管理者認証を行っています。");
    update();
    m_installer.start(QString::fromUtf8(PKEXEC_PATH), arguments);
  }

  void reset_calibration()
  {
    if (m_phase == Phase::Applying) {
      return;
    }

    m_result.reset();
    m_resetting = true;
    m_phase = Phase::Applying;
    m_message = tr("保存済みの補正を初期化しています。");
    update();
    m_installer.start(
      QString::fromUtf8(PKEXEC_PATH),
      {QString::fromUtf8(INSTALL_HELPER_PATH), QStringLiteral("--reset")});
  }

  void restart()
  {
    if (m_phase == Phase::Applying) {
      return;
    }
    m_measured.clear();
    m_result.reset();
    m_phase = Phase::Calibrating;
    m_message.clear();
    update();
  }

  bool m_allow_mouse;
  Phase m_phase = Phase::Calibrating;
  std::vector<calibration::Point> m_measured;
  calibration::Matrix m_final_matrix;
  std::optional<calibration::FitResult> m_result;
  QString m_message;
  QString m_device_error;
  QProcess m_installer;
  std::unique_ptr<QSocketNotifier> m_stylus_notifier;
  int m_stylus_fd = -1;
  int m_raw_x = 0;
  int m_raw_y = 0;
  int m_x_min = 0;
  int m_x_max = 1;
  int m_y_min = 0;
  int m_y_max = 1;
  bool m_pending_tip_down = false;
  bool m_resetting = false;
};

} // namespace

int main(int argc, char *argv[])
{
  QApplication application(argc, argv);
  QCoreApplication::setApplicationName(QStringLiteral("surface-pen-calibrate"));
  QCoreApplication::setApplicationVersion(QStringLiteral("0.2.0"));

  QCommandLineParser parser;
  parser.setApplicationDescription(
    QObject::tr("Surface Penのlibinput座標補正行列を測定します。"));
  parser.addHelpOption();
  parser.addVersionOption();
  QCommandLineOption allow_mouse(
    QStringLiteral("allow-mouse"),
    QObject::tr("開発時のテスト用にマウスクリックを受け付けます。"));
  parser.addOption(allow_mouse);
  parser.process(application);

  CalibrationWindow window(parser.isSet(allow_mouse));
  window.showFullScreen();
  window.activateWindow();
  window.setFocus();

  QTimer::singleShot(0, [&window] {
    QScreen *screen = window.screen();
    if (screen != nullptr &&
        screen->orientation() != screen->primaryOrientation()) {
      window.setCursor(QCursor(Qt::ArrowCursor));
      QMessageBox::critical(
        &window,
        QObject::tr("画面の向きが正しくありません"),
        QObject::tr("Surfaceを通常の横向きへ戻してから、"
                    "キャリブレーションを起動し直してください。"));
      window.close();
    }
  });

  return application.exec();
}
