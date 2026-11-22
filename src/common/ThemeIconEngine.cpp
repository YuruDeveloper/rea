#include "ThemeIconEngine.h"

#include "Configuration.h"

#include <QApplication>
#include <QFile>
#include <QFileInfo>
#include <QPainter>
#include <QPalette>
#include <QRegularExpression>
#include <QSvgRenderer>

ThemeIconEngine::ThemeIconEngine(const QString &filename) : plainIcon(filename)
{
    const QFileInfo info(filename);
    const QString soulFilename = info.path() + "/soul/" + info.fileName();
    QFile file(QFile::exists(soulFilename) ? soulFilename : filename);
    if (file.open(QFile::ReadOnly)) {
        svgData = file.readAll();
    }
}

void ThemeIconEngine::paint(QPainter *painter, const QRect &rect, QIcon::Mode mode,
                            QIcon::State state)
{
    if (!Config()->usesSoulStylesheet()) {
        plainIcon.paint(painter, rect, Qt::AlignCenter, mode, state);
        return;
    }

    const QPalette palette = qApp->palette();
    QColor color = palette.color(QPalette::Active, QPalette::Text);
    if (mode == QIcon::Selected) {
        color = palette.color(QPalette::Active, QPalette::HighlightedText);
    } else if (mode == QIcon::Disabled) {
        color = palette.color(QPalette::Disabled, QPalette::Text);
    }

    // Only a color with the "#" notation changes. Thus "none" and a reference stay as they are.
    static const QRegularExpression colorRegExp("\\b((?:fill|stroke)(?:=\"|:)\\s*)#[0-9a-fA-F]+");
    QString xml = QString::fromUtf8(svgData);
    xml.replace(colorRegExp, "\\1" + color.name());

    QSvgRenderer renderer(xml.toUtf8());
    renderer.setAspectRatioMode(Qt::KeepAspectRatio);
    renderer.render(painter, rect);
}

QIconEngine *ThemeIconEngine::clone() const
{
    return new ThemeIconEngine(*this);
}

QPixmap ThemeIconEngine::pixmap(const QSize &size, QIcon::Mode mode, QIcon::State state)
{
    if (!Config()->usesSoulStylesheet()) {
        return plainIcon.pixmap(size, mode, state);
    }

    QPixmap pix(size);
    pix.fill(Qt::transparent);
    {
        QPainter painter(&pix);
        paint(&painter, QRect(QPoint(0, 0), size), mode, state);
    }
    return pix;
}

QSize ThemeIconEngine::actualSize(const QSize &size, QIcon::Mode mode, QIcon::State state)
{
    return plainIcon.actualSize(size, mode, state);
}
