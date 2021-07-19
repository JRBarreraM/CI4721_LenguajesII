%{
    #include <vector>
    #include <iostream>
    #include <regex>
    #include "token.hpp"
    #include "ast.hpp"
    #include "symbol_table.hpp"
    using namespace std;

    extern int yylex(void);
    extern int yylineno;
    extern int yycolumn;
    extern char *yytext;

    // queues for tokens and errors
    extern queue<string> errors;
    queue<string> st_errors;
    vector<Token*> detectedTokens;
    queue<string> type_errors;
    queue<string> custom_errors;
    bool func_has_return = false;
    string actual_func_id = "";
    string type_elem_array = "";
    bool all_same_type = true;

    void yyerror(const char *s);
    void redeclared_variable_error(string id);
    bool check_id_exists(string id);
    bool check_func_args(string id, NodeCallFunctionArgs* args);
    void calcNumOfArgs(string id, NodeRoutineArgsDef* args);
    regex extension("(.*)\\.eula");

    NodeStart* root_ast;
    sym_table st;
%}

%union 
{	
  int   integer;
  float flot;
  bool  boolean;
  char* str;
  char  ch;
  node* ast;
  NodeStart* ns;
  NodeRoutineArgsDef* nrad;
  NodeCallFunctionArgs* ncfa;
}

%define parse.lac full
%define parse.error simple

%locations
%start Start

/* Declaraciones de BISON */
%token SEMICOLON 1
%token COMMA 2
%token DOT 3
%token DTWODOTS 4
%token SOFORTH 5
%token ASSIGN 6
/*  */
%token LET 7
%token <str> TINT 8
%token <str> TBOOL 9
%token <str> TFLOAT 10
%token <str> TCHAR 11
%token <str> TSTR 12
%token TSTRUCT 13
%token TUNION 14
%token <str> TLIST 15
%token TILDE 16
%token DEREF 17
%token ROOF 18
/*  */
%token FUNC 19
%token PROC 20
%token IF 21
%token ELIF 22
%token ELSE 23
/*  */
%token FOR 24
%token IN 25
%token WHILE 26
%token RETURN 27
/*  */
%token PRINT 28
%token INPUT 29
/*  */
%token NEW 30
%token VENGEANCE 31
/*  */
%token OCURLYBRACKET 32
%token CCURLYBRACKET 33
%token OBRACKET 34
%token CBRACKET 35
%token OPAR 36
%token CPAR 37
/*  */
%token <str> ADD 38
%token <str> SUB 39
%token <str> MUL 40
%token <str> DIV 41
%token <str> MOD 42
%token <str> POW 43
%token PLUSPLUS 44
%token MINUSMINUS 45
%token <str> NOT 46
%token <str> OR 47
%token <str> AND 48
%token <str> EQUALS 49
%token <str> NEQUALS 50
%token <str> GREATER 51
%token <str> LESS 52
%token <str> GEQ 53
%token <str> LEQ 54
%token <str> BREAK 55
%token <str> CONTINUE 56

%token <integer>  NUMBER 57
%token <flot>     DECIMAL 58
%token <str>      ID 59
%token <ch>       CHAR 60
%token <str>      STRING 61
%token <boolean>  TRUE 62
%token <boolean>  FALSE 63

%type <ast>     Inst InstAux Action FuncBody 
%type <ast>     Definition Type TypeAux TypePrimitive TypeComposite ProcSignature
%type <ast>     VarInst VarDef OptAssign Assign RValue InputType OptExp Exp
%type <ast>     LValue DefFunc CallFunc FuncSignature
%type <ncfa>    ArgElems ArgList
%type <nrad>    ParList FuncPar
%type <ast>     DefProc Array ArrExp ArrElems DefUnion UnionBody DefStruct StructBody
%type <ast>     Selection If OptElif Elif OptElse For Range While LoopWhile
%type <boolean> OptRoof
%type <ns>      Start
%type <str>     IdFor Func Proc

// Precedence

%left       EQUALS NEQUALS
%left       OR AND 
%nonassoc   LESS LEQ GREATER GEQ
%right      NOT
%nonassoc   ASSIGN SOFORTH
%left       ADD SUB
%left       MUL DIV MOD
%right      POW
%left       OBRACKET CBRACKET
%right      DEREF
%left       DOT
%nonassoc   ID
%left       OPAR

%expect 0
/* Gramatica del lenguaje */
%%

/* Estructura del programa */
Start:          Inst                  { $$ = new NodeStart($1); root_ast = $$;}
                | /* lambda */        { $$ = NULL; }
;
Inst:           InstAux               { $$ = new NodeInst($1); }
                | Inst InstAux        { $$ = new NodeInst($2, $1); }
;
InstAux:        Action                { $$ = $1; }
	            | Definition          { $$ = $1; }
;
Action:         VarInst SEMICOLON               { $$ = $1; }
                | CallFunc SEMICOLON            { $$ = $1; }
                | Selection                     { $$ = $1; }
                | While                         { $$ = $1; }
                | For                           { $$ = $1; }
                | VENGEANCE LValue SEMICOLON    { $$ = new NodeVengeance($2); }
                | PRINT OPAR Exp CPAR SEMICOLON { $$ = new NodePrint($3); }
                | CONTINUE SEMICOLON            { $$ = new NodeContinue(); }
                | BREAK SEMICOLON               { $$ = new NodeBreak(); }
                | ID PLUSPLUS SEMICOLON         { t_type* tipo;
                                                  if (check_id_exists($1)){
                                                    string s = st.lookup($1)->type->get_name();
                                                    arithmeticUnOPType(s);
                                                  }
                                                  else tipo = t_type_error::instance();
                                                  $$ = new NodeAssign(new NodeIDLValue($1), new NodeBinaryOperator(new NodeIDLValue($1), "+", new NodeINT(1), tipo));
                                                }   
                | ID MINUSMINUS SEMICOLON       { t_type* tipo;
                                                  if (check_id_exists($1)){
                                                    string s = st.lookup($1)->type->get_name();
                                                    arithmeticUnOPType(s);
                                                  }
                                                  else tipo = t_type_error::instance();
                                                  $$ = new NodeAssign(new NodeIDLValue($1), new NodeBinaryOperator(new NodeIDLValue($1), "-", new NodeINT(1), tipo));
                                                }
                | RETURN Exp SEMICOLON          { if (actual_func_id == ""){custom_errors.push("syntax error\: 'return' outside function at line " + to_string(yylineno) + "\n");}
                                                    else{checkExpectedType(st.lookup(actual_func_id)->type->get_name(),$2->return_type()->get_name()); 
                                                        if (st.get_top_scope() == dynamic_cast<extra_info_func*>(st.lookup(actual_func_id)->extra_inf)->child_scope){ func_has_return = true; }} $$ = new NodeReturn($2);}
; 
FuncBody:       Inst                { $$ = $1; }
	            | /* lambda */      { $$ = NULL; }
;
Definition:     DefUnion          { $$ = $1; }
                | DefStruct       { $$ = $1; }
                | DefProc         { $$ = $1; }
                | DefFunc         { $$ = $1; }
                | FuncSignature   { $$ = $1; }
                | ProcSignature   { $$ = $1; }
;

/* Tipos */
Type:           TypeAux                                 { $$ = $1; }
                | TLIST OBRACKET Type CBRACKET          { $$ = new NodeTypeList($3);} /*Pendiente Recursion*/
                | Type OBRACKET Exp CBRACKET            { checkExpectedType("int",$3->return_type()->get_name()); $$ = new NodeTypeArrayDef($1, $3); } /*Pendiente Recursion*/
                | TypeAux TILDE  	                    { $$ = new NodeTypePointerDef($1); } /*Pendiente Recursion*/
;

TypeAux:        TypePrimitive                      { $$ = $1; }
                | TypeComposite                    { $$ = $1; }
;

TypePrimitive:  TBOOL                              { $$ = new NodeTypePrimitiveDef(t_type_bool::instance()); }
                | TCHAR                            { $$ = new NodeTypePrimitiveDef(t_type_char::instance()); }
                | TINT                             { $$ = new NodeTypePrimitiveDef(t_type_int::instance()); }
                | TFLOAT                           { $$ = new NodeTypePrimitiveDef(t_type_float::instance()); }
;
                
TypeComposite:  TSTR                               { $$ = new NodeTypePrimitiveDef(t_type_str::instance()); }
                | ID                               { $$ = new NodeTypePrimitiveDef(new t_type($1)); } //Check this
;

/* Definiciones */
VarInst:        VarDef                    { $$ = $1; }
	            | Assign                  { $$ = $1; }
;
VarDef:         LET Type ID OptAssign     { if ($4 != NULL && ($2->return_type()->get_name() != $4->return_type()->get_name())) push_type_error("assign", $2->return_type()->get_name(), $4->return_type()->get_name());
                                            $$ = new NodeVarDef($2, $3, $4);
                                            if(!st.insert($3,"var",$2->return_type(), $4 != NULL )) redeclared_variable_error($3);}
;
OptAssign:      ASSIGN RValue             { $$ = $2; }
	            | /* lambda */            { $$ = NULL; }
;
Assign:         LValue ASSIGN RValue      { if ($1->return_type()->get_name() != $3->return_type()->get_name()) push_type_error("assign", $1->return_type()->get_name(), $3->return_type()->get_name());
                                            $$ = new NodeAssign($1, $3); }
;
RValue:         Exp                                             { $$ = $1; }
                | Array                                         { $$ = $1; }
                | NEW Type                                      { $$ = new NodeNew($2); }
                | INPUT OPAR OptExp CPAR DTWODOTS InputType     { $$ = new NodeInput($6, $3); }
;
InputType:      TypePrimitive   { $$ = $1; }
                | TSTR          { $$ = new NodeTypePrimitiveDef(t_type_str::instance()); }
;
OptExp:         Exp                  { $$ = $1; }
                | /* Lambda */       { $$ = NULL; }
;
/* Expresiones */
Exp:            NUMBER               { $$ = new NodeINT($1); }
                | DECIMAL            { $$ = new NodeFLOAT($1); }
                | LValue             { $$ = $1; }
                | TRUE               { $$ = new NodeBOOL(true); }
                | FALSE              { $$ = new NodeBOOL(false); }
                | CHAR               { $$ = new NodeCHAR($1); }
                | STRING             { $$ = new NodeSTRING($1); }
                | CallFunc           { $$ = $1; }
                | Exp ADD Exp        { $$ = new NodeBinaryOperator($1, $2, $3, arithmeticBinOPType($1->return_type()->get_name(),$3->return_type()->get_name()));}
                | Exp SUB Exp        { $$ = new NodeBinaryOperator($1, $2, $3, arithmeticBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp MUL Exp        { $$ = new NodeBinaryOperator($1, $2, $3, arithmeticBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp DIV Exp        { $$ = new NodeBinaryOperator($1, $2, $3, arithmeticBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp MOD Exp        { $$ = new NodeBinaryOperator($1, $2, $3, arithmeticBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | SUB Exp            { $$ = new NodeUnaryOperator($1, $2, arithmeticUnOPType($2->return_type()->get_name())); }
                | Exp POW Exp        { $$ = new NodeBinaryOperator($1, $2, $3, arithmeticBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | OPAR Exp CPAR      { $$ = $2; }
                | Exp AND Exp        { $$ = new NodeBinaryOperator($1, $2, $3, booleanBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp OR Exp         { $$ = new NodeBinaryOperator($1, $2, $3, booleanBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp EQUALS Exp     { $$ = new NodeBinaryOperator($1, $2, $3, equalsType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp NEQUALS Exp    { $$ = new NodeBinaryOperator($1, $2, $3, equalsType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp GREATER Exp    { $$ = new NodeBinaryOperator($1, $2, $3, comparisonBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp LESS Exp       { $$ = new NodeBinaryOperator($1, $2, $3, comparisonBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp GEQ Exp        { $$ = new NodeBinaryOperator($1, $2, $3, comparisonBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | Exp LEQ Exp        { $$ = new NodeBinaryOperator($1, $2, $3, comparisonBinOPType($1->return_type()->get_name(),$3->return_type()->get_name())); }
                | NOT Exp            { $$ = new NodeUnaryOperator($1, $2, booleanUnOPType($2->return_type()->get_name())); }
                | LValue OBRACKET Exp SOFORTH Exp CBRACKET  { checkExpectedType("int",$3->return_type()->get_name());
                                                              checkExpectedType("int",$5->return_type()->get_name());
                                                              $$ = new NodeSubArray($1, $3, $5); }
;

/* Left Values */
LValue:         ID                             { check_id_exists($1);
                                                $$ = new NodeIDLValue($1); }
                | LValue OBRACKET Exp CBRACKET { checkExpectedType("int",$3->return_type()->get_name()); $$ = new NodeArrayLValue($1, $3); }
                | LValue DOT ID                { check_id_exists($3);
                                                  $$ = new NodeLValueDot($1, $3); }
                | DEREF LValue                 { $$ = new NodePointerLValue($2); }
;

/* Funciones */
DefFunc:        Func OPAR FuncPar {calcNumOfArgs($1,$3);} CPAR OCURLYBRACKET FuncBody CCURLYBRACKET { $$ = new NodeFuncDef($1, $3, $7); st.exit_scope(); actual_func_id = ""; 
                    if (!func_has_return){
                        string t($1); custom_errors.push("syntax error\: function '" + t + "' has no return at line " + to_string(yylineno) + "\n");
                    } func_has_return = false;}
;
Func: FUNC TypePrimitive DTWODOTS ID     { if(!st.insert($4,"func",$2->return_type(),true, new extra_info_func(st.get_last_scope()+1,-1))) redeclared_variable_error($4);
                                            st.new_scope(); $$ = $4; actual_func_id = $4;}
;

FuncSignature:  MUL FUNC TypePrimitive DTWODOTS ID OPAR FuncPar CPAR SEMICOLON { if(!st.insert($5,"func", $3->return_type(), false)) 
                                                                                    redeclared_variable_error($5); 
                                                                                $$ = new NodeFuncSignature($5,$7,$3); }
;

FuncPar:        ParList                 { $$ = $1; }
                | /* lambda */          { $$ = NULL; }
;

ParList:        ParList COMMA Type OptRoof ID   { $$ = new NodeRoutineArgsDef($3, $4, $5, $1); 
                                                  if(!st.insert($5, "var", $3->return_type(), true)) redeclared_variable_error($5);}
                | Type OptRoof ID               { $$ = new NodeRoutineArgsDef($1, $2, $3); 
                                                  if(!st.insert($3, "var", $1->return_type(), true)) redeclared_variable_error($3);}
;

OptRoof:        ROOF                    { $$ = true; }
                | /* Lambda */          { $$ = false; }
;

CallFunc:       ID OPAR ArgElems CPAR { if (check_id_exists($1)) check_func_args($1,$3);
                                        $$ = new NodeCallFunction($1, $3); }
;

ArgElems:   ArgList                             { $$ = $1; }
	        | /* lambda */                      { $$ = NULL; }
;

ArgList:    RValue                              { $$ = new NodeCallFunctionArgs($1); }
            | ArgList COMMA RValue              { $$ = new NodeCallFunctionArgs($3, $1); }
;

/* Procedimientos */
DefProc:        Proc OPAR FuncPar {calcNumOfArgs($1,$3);} CPAR OCURLYBRACKET FuncBody CCURLYBRACKET { $$ = new NodeProcDef($1, $3, $7);
                                                                                 st.exit_scope(); }
;
Proc:           PROC ID   { if(!st.insert($2, "proc", t_type_no_type::instance(), true, new extra_info_func(st.get_last_scope()+1,-1))) redeclared_variable_error($2);
                            st.new_scope();
                            $$ = $2; }
;
ProcSignature:   MUL PROC ID OPAR FuncPar CPAR SEMICOLON { if(!st.insert($3,"func", t_type_no_type::instance(), false)) redeclared_variable_error($3); 
                                                           $$ = new NodeProcSignature($3, $5); }
;

/* Arreglos */
Array:          OBRACKET ArrExp CBRACKET   { $$ = new NodeArray($2); type_elem_array = "";}
;

ArrExp:         ArrElems                { $$ = $1; if (!all_same_type){ type_errors.push("type error: not all elements in array have the same type at line " + to_string(yylineno) + "\n"); } }
                | Exp SOFORTH Exp       { checkExpectedType("int",$1->return_type()->get_name()); checkExpectedType("int",$3->return_type()->get_name()); $$ = new NodeArrayRange($1, $3); }
;

ArrElems:       ArrElems COMMA RValue    { $$ = new NodeArrayElems($3, $1); if (type_elem_array != $3->return_type()->get_name()){all_same_type = false;} }
		        | RValue                 { $$ = new NodeArrayElems($1); type_elem_array = $1->return_type()->get_name(); }
;

/* Union */
DefUnion:       Union ID OCURLYBRACKET UnionBody CCURLYBRACKET   { $$ = new NodeUnionDef($2, $4);
                                                                    st.exit_scope();
                                                                    if(!st.insert($2, "union", t_type_union::instance(), true)) redeclared_variable_error($2); }
;

Union:          TUNION      { st.new_scope(); }
;

UnionBody:      LET Type ID SEMICOLON                 { $$ = new NodeUnionFields($3, $2); 
                                                        if(!st.insert($3, "var", $2->return_type(), false)) redeclared_variable_error($3); }
		        | UnionBody LET Type ID SEMICOLON     { $$ = new NodeUnionFields($4, $3, $1); 
                                                        if(!st.insert($4, "var", $3->return_type(), false)) redeclared_variable_error($4); }
;

/* Struct */
DefStruct:      Struct ID OCURLYBRACKET StructBody CCURLYBRACKET { $$ = new NodeStructDef($2, $4); 
                                                                    st.exit_scope();
                                                                    if(!st.insert($2, "struct", t_type_struct::instance(), true)) redeclared_variable_error($2); }
;
Struct:         TSTRUCT     { st.new_scope(); }
;

StructBody:     VarDef SEMICOLON                { $$ = new NodeStructFields($1); }
		        | StructBody VarDef SEMICOLON   { $$ = new NodeStructFields($2, $1); }
;

/* Condicionales */
Selection:      If OCURLYBRACKET Inst CCURLYBRACKET OptElif OptElse { $$ = new NodeConditional($1, $3, $5, $6); st.exit_scope(); }
;
If:             IF OPAR Exp CPAR     { checkExpectedType("bool",$3->return_type()->get_name()); $$= $3; st.new_scope(); }
;

OptElif:        Elif OCURLYBRACKET Inst CCURLYBRACKET OptElif     { $$ = new NodeElif($1, $3, $5); st.exit_scope(); }
                | /* lambda */                                                  { $$ = NULL; }
;
Elif:           ELIF OPAR Exp CPAR   { checkExpectedType("bool",$3->return_type()->get_name()); $$= $3; st.new_scope(); }
;

OptElse:        Else OCURLYBRACKET Inst CCURLYBRACKET   { $$ = new NodeElse($3); st.exit_scope(); }
		        |       /* lambda */                    { $$ = NULL; }
;
Else:           ELSE    { st.new_scope(); }
;

/* For Loop */
For:            LoopFor OPAR IdFor IN Range CPAR OCURLYBRACKET Inst CCURLYBRACKET    { $$ = new NodeFor($3, $5, $8); st.exit_scope(); }
;
LoopFor:        FOR     { st.new_scope(); }
;
IdFor:          ID      { $$ = $1; 
                          if(!st.insert($1, "var", t_type_int::instance(),true)) redeclared_variable_error($1);}
;

Range:          Exp         { $$ = $1; }
                | Array     { $$ = $1; }
;

/* While Loop */
While:          LoopWhile  OCURLYBRACKET Inst CCURLYBRACKET    { $$ = new NodeWhile($1, $3); st.exit_scope(); }
;
LoopWhile:      WHILE OPAR Exp CPAR  { checkExpectedType("bool",$3->return_type()->get_name()); $$=$3; st.new_scope(); }
;
%%

void yyerror(const char *s)
{
    fprintf(stderr, "Error: %s, unexpected token %s at line %d, column %d\n", s, yytext,yylineno, yycolumn);
}

void redeclared_variable_error(string id)
{
    string e = "Error: redeclared variable " + id + " at line " + to_string(yylineno) + ", column " + to_string(yycolumn) + "\n";
    st_errors.push(e);
}

bool check_id_exists(string id)
{
    if(st.lookup(id) == NULL)
    {
        string e = "Error: " + id + " not declared. At line " + to_string(yylineno) + ", column " + to_string(yycolumn) + "\n";
        st_errors.push(e);
        return false;
    }
    return true;
}

void calcNumOfArgs(string id, NodeRoutineArgsDef* args) {
    NodeRoutineArgsDef* temp = args;
    symbol* lookUp = st.lookup(id);
    int numOfArgs = 0;
    while (temp){
        numOfArgs++;
        dynamic_cast<extra_info_func*>(lookUp->extra_inf)->args_types.insert(dynamic_cast<extra_info_func*>(lookUp->extra_inf)->args_types.begin(),temp->type->return_type());
        temp = temp->args;
    }
    dynamic_cast<extra_info_func*>(lookUp->extra_inf)->numOfArgs = numOfArgs;
}

bool check_func_args(string id, NodeCallFunctionArgs* args){
    symbol* s = st.lookup(id);
    NodeCallFunctionArgs* temp = args;
    vector<node*> args_list;
    while (temp){
        args_list.insert(args_list.begin(),temp->rvalue);
        temp = temp->head;
    }
    int numOfArgs = dynamic_cast<extra_info_func*>(s->extra_inf)->numOfArgs;
    if (args_list.size() != numOfArgs){
        string e = "Error: " + id + " takes " + to_string(numOfArgs) + " arguments but " + to_string(args_list.size()) + " were given at line " + to_string(yylineno) + "\n";
        st_errors.push(e);
        return false;
    }
    bool result = true;
    for (int i=0; i < args_list.size() ; i++){
        result = result && checkExpectedType(dynamic_cast<extra_info_func*>(s->extra_inf)->args_types[i]->get_name(),args_list[i]->return_type()->get_name());
    }
    return result;
}

int main(int argc, char **argv)
{
    bool lex = false;
    bool ast = false;
    bool stp = false;
    int flags = 0;
    for(int i = 1; i < argc -1; ++i) {
        if(string(argv[i]) == "-lex") {
            lex = true;
            flags++;
        }

        else if(string(argv[i]) == "-ast") {
            ast = true;
            flags++;
        }
        else if(string(argv[i]) == "-st") {
            stp = true;
            flags++;
        }

        else{
            cout << "Unexpected argument: " << argv[i] <<endl;
            return 0;
        }
    }

    // Look for input line
    if(argc < 2 + flags)
    {
        cout << "No input file" << endl;
        return -1;
    }

    if(!regex_match(argv[argc-1], extension))
    {
        cout << "File extension doesn't match." << endl;
        return -1;
    }

    // open file to extract the tokens
    extern FILE *yyin;
    yyin = fopen(argv[argc-1], "r");

    // check if file was succesfully opened.
    if (!yyin) 
    {
        cout << "There was an error opening the file" << endl;
        return -1;
    }

    // apply lexing
    int tok;
    while(tok = yylex())
    {
        switch(tok)
        {
            case ID:
                detectedTokens.push_back(new TIdentifier(yylval.str, tok, yylineno, yylloc.first_column));
                break;
            case NUMBER:
                detectedTokens.push_back(new TInteger(yylval.integer, tok, yylineno, yylloc.first_column));
                break;
            case DECIMAL:
                detectedTokens.push_back(new TFloat(yylval.flot, tok, yylineno, yylloc.first_column));
                break;
            case STRING:
                detectedTokens.push_back(new TIdentifier(yylval.str, tok, yylineno, yylloc.first_column));
                break;
            case CHAR:
                detectedTokens.push_back(new TChar(yylval.ch, tok, yylineno, yylloc.first_column));
                break;
            default:
                detectedTokens.push_back(new Token(tok, yylineno, yylloc.first_column));
                break;
        }
    };

    fclose(yyin);
    yyin = fopen(argv[argc-1], "r");

    // If error on lexer, show them
    if(!errors.empty()){
        show_queue(errors);
    }

    // Print tokens
    if (lex){
        print_tokens(detectedTokens);
    }
    
    // reset lines and columns
    yylineno = 1;
    yycolumn = 1;

    // start parsing
    yyparse();

    if(ast) root_ast->print(0);
    if(stp) st.print();
    if(!custom_errors.empty()) show_queue(custom_errors);
    if(!st_errors.empty()) show_queue(st_errors);
    if(!type_errors.empty()) show_queue(type_errors);

    return 0;
}