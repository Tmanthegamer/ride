%{
/* need this for the call to atoi(), atof() below */
#include <math.h>
#include <string.h>
#include "ObjectTree.h"
#include "rix.tab.h" /* Generated by bison. */
#include "rixc.h"
#include "error.h"

#define INSERT_BUFF_LEN 1024
#define INDENT_STACK_MAX 512

int g_current_line_indent = 0;
int g_indent_levels[INDENT_STACK_MAX];
int g_indent_levels_index = -1;
int g_is_fake_outdent_symbol = 0;

int  stack_top() { return  g_indent_levels[g_indent_levels_index]; }
int  stack_pop() { return  g_indent_levels[g_indent_levels_index--]; }
void stack_push(int val) { g_indent_levels[++g_indent_levels_index] = val; }
extern int g_lineNum;
extern int g_lineCol;

#define YY_USER_INIT { \
    stack_push(0); \
    BEGIN(initial); \
}

//#define YY_DECL extern int yylex ( YYSTYPE * lvalp, YYLTYPE * llocp, yyscan_t scanner )


int yycolumn = 1;
void set_yycolumn(int val) {
    yycolumn = val;
    g_lineCol = yycolumn; //first column
    //yylloc.last_column = yycolumn + yyleng - 1;
}

#define YY_USER_ACTION { \
    g_lineNum = yylineno; \
    set_yycolumn(yycolumn);\
    yycolumn += yyleng; \
}

char* handleCodeInsert(void);
void* handleComma(void);

%}

%option yylineno
%option noyywrap

%x initial
%x indent
%s normal

%option bison-bridge bison-locations

alphabetic    [a-zA-Z]
numeral       [0-9]
alphanumeric  {alphabetic}|{numeral}
integer       {numeral}+
decimal       "."{numeral}+|{numeral}+"."{numeral}+
float         {decimal}|(({decimal}|{integer})[eE][-+]?{integer})
string        \"(\\.|[^\\"])*\"
char          \'(\\.|[^\\'])+\'
comment       \/\/.*

colon         ":"
paramComma    ","
classDec      "::"
classDecPrim  ":::"
conditionLink "?"
selfIdent     "$"
hash          "#"

identifier    ({selfIdent})*({alphabetic}|"_")({alphanumeric}|"_")*({selfIdent})*

unaryNegate   "-"

mathOp        "+"|"*"|"/"|"^^"|"%"
assignment    "="
return        "->"

lessThan      "<"
greaterThan   ">"
mathAssign    "+="|"-="|"*="|"/="
comparison    "<="|">="|"=="|"!="
ternary       "<>"
bitwiseOp     "&"|"^"|"|"|"~"|">>"|"<<"
booleanOp     "||"|"&&"

condReturn    "-->"
implies       "==>"
accessor      "."

dtvExternal  "##external"
dtvAddsource "##addsource"
%%
        int indent_caller = normal;

<*>\n { set_yycolumn(0); yylineno--; REJECT; }
<initial>.  { set_yycolumn(yycolumn-1); indent_caller = normal; yyless(0); BEGIN(indent); }
<initial>\n { indent_caller = normal; yyless(0); BEGIN(indent); return ENDOFLINE; }

<indent>" "     { g_current_line_indent++; }
<indent>\t      { g_current_line_indent++; }
<indent>\n      { g_current_line_indent = 0; /* ignoring blank line */ }
<indent><<EOF>> {
                    // When encountering the end of file, we want to emit an
                    // outdent for all indents currently left.
                    if(stack_top() != 0) {
                        stack_pop();

                        // See the same code below (<indent>.) for a rationale.
                        if(g_current_line_indent != stack_top()) {
                            size_t i;
                            unput('\n');
                            for(i = 0 ; i < stack_top() ; ++i) {
                                unput(' ');
                            }
                        } else {
                            BEGIN(indent_caller);
                        }

                        compilerDebugPrintf("lexer: EOF OUTDENT\n");
                        decPrev(); //for tracking last-statement.
                        return UNINDENT;
                    } else {
                        yyterminate();
                    }
                }

<indent>.       {
                    if(!g_is_fake_outdent_symbol) {
                        unput(*yytext);
                    }
                    g_is_fake_outdent_symbol = 0;
                    // -2: -1 for putting it back and -1 for ending at the last space.
                    set_yycolumn(yycolumn-1);

                    // Indentation level has increased. It can only ever
                    // increase by one level at a time. Remember how many
                    // spaces this level has and emit an indentation token.
                    if(g_current_line_indent > stack_top()) {
                        compilerDebugPrintf("lexer: INDENT\n");
                        stack_push(g_current_line_indent);
                        BEGIN(indent_caller);
                        incPrev(); //for tracking last-statement.
                        return INDENT;
                    } else if(g_current_line_indent < stack_top()) {
                        compilerDebugPrintf("lexer: OUTDENT\n");
                        // Outdenting is the most difficult, as we might need to
                        // outdent multiple times at once, but flex doesn't allow
                        // emitting multiple tokens at once! So we fake this by
                        // 'unput'ting fake lines which will give us the next
                        // outdent.
                        stack_pop();

                        if(g_current_line_indent != stack_top()) {
                            size_t i;
                            // Unput the rest of the current line, including the newline.
                            // We want to keep it untouched.
                            for(i = 0 ; i < g_current_line_indent ; ++i) {
                                unput(' ');
                            }
                            unput('\n');
                            // Now, insert a fake character indented just so
                            // that we get a correct outdent the next time.
                            unput('.');
                            // Though we need to remember that it's a fake one
                            // so we can ignore the symbol.
                            g_is_fake_outdent_symbol = 1;
                            for(i = 0 ; i < stack_top() ; ++i) {
                                unput(' ');
                            }
                            unput('\n');
                        } else {
                            BEGIN(indent_caller);
                        }
                        decPrev(); //for tracking last-statement.
                        return UNINDENT;
                    } else {
                        // No change in indentation, not much to do here...
                        BEGIN(indent_caller);
                    }
                }

<normal>\n    { compilerDebugPrintf("EOL\n");
                g_current_line_indent = 0;
                indent_caller = YY_START;
                BEGIN(indent);
                return ENDOFLINE; }

[/][*][^*]*[*]+([^*/][^*]*[*]+)*[/]       { /* DO NOTHING */ }
[/][*]                                    { criticalError(ERROR_ParseError, "unterminated comment\n"); }
"`"			  {yylval -> sval =  handleCodeInsert(); return CODE_INSERT; }
{comment}     { compilerDebugPrintf("lexer: comment (ignored)\n"); /* do not forward comments at this time.*/ }
{string}      { compilerDebugPrintf("lexer: string\n"); yylval->sval = strdup(yytext); return STRING; }
{integer}     { compilerDebugPrintf("lexer: int\n");    yylval->ival = atoi(yytext);   return INT; }
{char}     { compilerDebugPrintf("lexer: char\n");    yylval->sval = strdup(yytext);   return CHAR; }
{float}       { compilerDebugPrintf("lexer: float\n");  yylval->fval = atof(yytext);   return FLOAT; }
{mathOp}      { compilerDebugPrintf("lexer: mathOp\n"); yylval->sval = strdup(yytext); return MATH_OP; }

{hash}{identifier}  {   char* first = strtok(yytext, "#");
                        Object* exists = findByName(first);
                        if (!exists) {
                          compilerDebugPrintf("lexer: new identifier %s\n",first);
                          yylval->sval = strdup(first);
                          return NEWIDENT;
                        } else {
                          char error[1024];
                          snprintf(error, 1024, "Trying to recreate identifier %s\n", first);
                          criticalError(ERROR_ParseError, error);
                        }
                      }

{identifier}  { yylval->sval = strdup(yytext);
                        Object* exists = findByName(yytext);
                        if (!exists) {
                          compilerDebugPrintf("lexer: unidentified identifier\n");
                          return UNMARKEDNEWIDENT;
                        } else if (exists->category == Variable) {
                          compilerDebugPrintf("lexer: identifier\n");
                          return IDENT;
                        } else if (isVerb(exists)) {
                          compilerDebugPrintf("lexer: verb\n");
                          return VERB;
                        } else if (exists->category == Type) {
                          compilerDebugPrintf("lexer: type\n");
                          return TYPE;
                        } else {
                          criticalError(ERROR_ParseError, "lexer: unidentified identifier\n");
                        }
                      }

{assignment}    { compilerDebugPrintf("lexer: assignment\n"); yylval->sval = strdup(yytext); return ASSIGNMENT; }
{conditionLink} { compilerDebugPrintf("lexer: CondLink\n");   yylval->sval = strdup(yytext); return CONDITIONLINK; }

{paramComma}    { compilerDebugPrintf("lexer: ParamComma\n"); yylval->sval = strdup(yytext); /*handleComma();*/ return PARAMCOMMA; }
{colon}         { compilerDebugPrintf("lexer: Colon\n");    yylval->sval = strdup(yytext); return COLON; }
{classDec}      { compilerDebugPrintf("lexer: ClassDec\n");   yylval->sval = strdup(yytext); return CLASSDEC; }
{classDecPrim}     { compilerDebugPrintf("lexer: CtorDecPrim\n");    yylval->sval = strdup(yytext); return CLASSDECPRIM; }
{return}        { compilerDebugPrintf("lexer: Return\n");     yylval->sval = strdup(yytext); return RETURN; }

{selfIdent}     { compilerDebugPrintf("lexer: self\n");       yylval->sval = strdup(yytext); return SELFIDENT; }

{unaryNegate}   { compilerDebugPrintf("lexer: Unary Negate\n");  yylval->sval = strdup(yytext); return UNARYNEGATE;  }

{booleanOp}     { compilerDebugPrintf("lexer: bitwiseOp\n");  yylval->sval = strdup(yytext); return BOOLEANOP;  }
{comparison}    { compilerDebugPrintf("lexer: comparator\n"); yylval->sval = strdup(yytext); return COMPARISON; }
{lessThan}    { compilerDebugPrintf("lexer: comparator<\n"); yylval->sval = strdup(yytext); return LESSTHAN; }
{greaterThan}    { compilerDebugPrintf("lexer: comparator>\n"); yylval->sval = strdup(yytext); return GREATERTHAN; }
{ternary}       { compilerDebugPrintf("lexer: ternary\n");                                   return TERNARY; }
{condReturn}    { compilerDebugPrintf("lexer: condReturn\n");                                return CONDRETURN; }
{mathAssign}    { compilerDebugPrintf("lefloatxer: MathAssign\n"); yylval->sval = strdup(yytext); return MATHASSIGN; }
{accessor}      { compilerDebugPrintf("lexer: accessor\n"); yylval->sval = strdup(yytext); return ACCESSOR; }

{hash}      { compilerDebugPrintf("lexer: accessor\n"); yylval->sval = strdup(yytext); return DESTRUCTOR; }

{dtvExternal}   { compilerDebugPrintf("lexer: directive\n"); yylval->sval = strdup(yytext); return DTV_EXTERNAL; }
{dtvAddsource}  { compilerDebugPrintf("lexer: directive\n"); yylval->sval = strdup(yytext); return DTV_ADDSOURCE; }

<<EOF>>       { return ENDOFFILE; }
[ \t]+        { g_lineCol += yyleng; } /* eat up whitespace */
"("           { compilerDebugPrintf("lexer: (\n"); return LPAREN; }
")"                             { compilerDebugPrintf("lexer: )\n"); return RPAREN; }
"["                             { compilerDebugPrintf("lexer: (\n"); return LBRACKET; }
"]"                             { compilerDebugPrintf("lexer: )\n"); return RBRACKET; }
"]"[ \t]*{assignment}           { compilerDebugPrintf("lexer: )\n"); return RBRACKETASSIGN; }
"{"           { compilerDebugPrintf("lexer: (\n"); return LBRACE; }
"}"           { compilerDebugPrintf("lexer: )\n"); return RBRACE; }
.             { compilerDebugPrintf("Unknown symbol encountered: '%s'\n", yytext); }

%%

char* handleCodeInsert(void) {
	 compilerDebugPrintf("lexer: code insert\n");
	 int c;
	 int index  = 0;
	 char * ci = (char*)malloc(INSERT_BUFF_LEN);
	 while ( c = input()) {
	 	if ( c != '`' && index < INSERT_BUFF_LEN ) {
	 		ci[index++] = c;
	 	}else if ( c == '`' ) {
	 		return ci;
	 	}
	 	if ( c == EOF ) {
		     criticalError(ERROR_ParseError, "unterminated code insert\n");
		     return 0;
		 }
	 }
}

void* handleComma(void) {
	 compilerDebugPrintf("lexer: eating spaces between commas\n");
	 int c;
	 while ( c = input()) {
        if ( c !=  '\t' || c != ' ') {
	 		return;
	 	}
	 }
}

