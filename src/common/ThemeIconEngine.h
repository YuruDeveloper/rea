#ifndef THEMEICONENGINE_H
#define THEMEICONENGINE_H

#include <QIcon>
#include <QIconEngine>

/**
 * @brief Icon engine for an SVG icon that follows the interface theme
 *
 * In the Paper and Dusk themes the engine paints the file in one color of the palette: the text
 * color, the color of selected text for a selected item, and the color of disabled text for a
 * disabled item. If the folder of the file has a folder "soul" with a file of the same name, the
 * engine paints that file. In the other themes the engine paints the usual icon of the file.
 */
class ThemeIconEngine : public QIconEngine
{
public:
    explicit ThemeIconEngine(const QString &filename);

    void paint(QPainter *painter, const QRect &rect, QIcon::Mode mode, QIcon::State state) override;
    QIconEngine *clone() const override;
    QPixmap pixmap(const QSize &size, QIcon::Mode mode, QIcon::State state) override;
    QSize actualSize(const QSize &size, QIcon::Mode mode, QIcon::State state) override;

private:
    QIcon plainIcon;
    QByteArray svgData;
};

#endif // THEMEICONENGINE_H
