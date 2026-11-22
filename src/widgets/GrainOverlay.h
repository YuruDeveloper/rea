#ifndef GRAINOVERLAY_H
#define GRAINOVERLAY_H

#include <QPixmap>
#include <QWidget>

/**
 * @brief Faint grain above all widgets of a window, for the Paper and Dusk themes
 *
 * The overlay has the size of its parent and stays above the other children. The mouse events go
 * to the widgets below it. In the other themes the overlay is hidden.
 */
class GrainOverlay : public QWidget
{
    Q_OBJECT

public:
    explicit GrainOverlay(QWidget *parent);

protected:
    void paintEvent(QPaintEvent *event) override;
    bool eventFilter(QObject *object, QEvent *event) override;

private:
    void applyTheme();

    QPixmap tile;
};

#endif // GRAINOVERLAY_H
