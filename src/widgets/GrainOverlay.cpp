#include "GrainOverlay.h"

#include "common/Configuration.h"

#include <QChildEvent>
#include <QEvent>
#include <QImage>
#include <QPaintEvent>
#include <QPainter>
#include <QRandomGenerator>

GrainOverlay::GrainOverlay(QWidget *parent) : QWidget(parent)
{
    setAttribute(Qt::WA_TransparentForMouseEvents);
    setAttribute(Qt::WA_NoSystemBackground);
    setFocusPolicy(Qt::NoFocus);

    // Black pixels with an opacity from 0 to 9 percent. The seed is constant, thus the grain is
    // the same in each session.
    const int tileSize = 160;
    const int maxAlpha = 23;
    QImage image(tileSize, tileSize, QImage::Format_ARGB32_Premultiplied);
    QRandomGenerator random(20261123);
    for (int y = 0; y < tileSize; y++) {
        for (int x = 0; x < tileSize; x++) {
            image.setPixel(x, y, qRgba(0, 0, 0, random.bounded(maxAlpha + 1)));
        }
    }
    tile = QPixmap::fromImage(image);

    parent->installEventFilter(this);
    for (QObject *sibling : parent->children()) {
        if (sibling != this) {
            sibling->installEventFilter(this);
        }
    }
    connect(Config(), &Configuration::interfaceThemeChanged, this, &GrainOverlay::applyTheme);
    applyTheme();
}

void GrainOverlay::paintEvent(QPaintEvent *event)
{
    QPainter painter(this);
    painter.drawTiledPixmap(event->rect(), tile, event->rect().topLeft());
}

bool GrainOverlay::eventFilter(QObject *object, QEvent *event)
{
    if (object == parent()) {
        if (event->type() == QEvent::Resize) {
            setGeometry(parentWidget()->rect());
        } else if (event->type() == QEvent::ChildAdded) {
            // A new child is above the overlay.
            static_cast<QChildEvent *>(event)->child()->installEventFilter(this);
            raise();
        }
    } else if (event->type() == QEvent::ZOrderChange && object->parent() == parent()) {
        // A sibling that calls raise() goes above the overlay.
        raise();
    }
    return QWidget::eventFilter(object, event);
}

void GrainOverlay::applyTheme()
{
    setGeometry(parentWidget()->rect());
    setVisible(Config()->usesSoulStylesheet());
    raise();
}
