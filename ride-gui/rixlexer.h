#ifndef RIXLEXER_H
#define RIXLEXER_H

#include <QObject>
#include <Qsci/qsciscintilla.h>
#include <Qsci/qscilexercustom.h>

class RixLexer : public QsciLexerCustom
{
    Q_OBJECT
public:
    void styleText(int start, int end) override;
    QString description(int style) const override;
    const char* language() const override;
private slots:
    void handleStyleNeeded(int pos);
};

#endif // RIXLEXER_H
