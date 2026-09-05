unit DUA.Conditionals;

interface

uses
  DUA.Types,
  DUA.Defines;

type
  /// <summary>
  ///   Evaluates the expression from a {$IF} or {$ELSEIF} directive.
  /// </summary>
  TConditionalEvaluator = record
  public
    /// <summary>
    ///   Returns tsUnknown for anything we cannot work out - an unrecognised symbol, a
    ///   function we do not model, or a syntax error. The caller is expected to warn and
    ///   take every branch rather than guess.
    /// </summary>
    class function Evaluate(const expression : string; const defines : IDefineSet) : TTriState; static;
  end;

implementation

uses
  System.Character,
  System.Math,
  System.SysUtils;

type
  TTokenKind = (
    tkEnd,          // past the last token
    tkIdentifier,
    tkNumber,
    tkLParen,
    tkRParen,
    tkEqual,        // =
    tkNotEqual,     // <>
    tkLess,         // <
    tkLessEqual,    // <=
    tkGreater,      // >
    tkGreaterEqual, // >=
    tkInvalid       // anything we do not recognise
  );

  TToken = record
    Kind : TTokenKind;
    Text : string;
    Number : double;
  end;

  /// <summary>
  ///   The kind of value an expression fragment produced. Unknown means we could not
  ///   work out even what sort of thing it is - an identifier we have never heard of,
  ///   for example. A boolean whose value we do not know is evkBoolean with a Bool of
  ///   tsUnknown, which is different: it still combines by the Kleene rules.
  /// </summary>
  TValueKind = (vkUnknown, vkBoolean, vkNumber);

  TValue = record
    Kind : TValueKind;
    Bool : TTriState;
    Number : double;
    function AsTriState : TTriState;
  end;

  TParser = class
  private
    FTokens : TArray<TToken>;
    FIndex : integer;
    FDefines : IDefineSet;
    FFailed : boolean;
    function Current : TToken;
    procedure Advance;
    function CurrentIsKeyword(const keyword : string) : boolean;
    procedure Fail;
    // Or > And > Not > Comparison > Primary. Note that unlike Pascal proper this binds
    // comparison tighter than and/or, so `A >= 1 and Defined(X)` means what an author
    // would expect rather than being a syntax error. Correctly parenthesised source
    // parses the same either way.
    function ParseExpression : TValue;
    function ParseOr : TValue;
    function ParseAnd : TValue;
    function ParseNot : TValue;
    function ParseComparison : TValue;
    function ParsePrimary : TValue;
    function ParseCallArgument(out argument : string) : boolean;
  public
    constructor Create(const tokens : TArray<TToken>; const defines : IDefineSet);
    function Parse : TTriState;
  end;

function MakeUnknown : TValue;
begin
  result.Kind := vkUnknown;
  result.Bool := tsUnknown;
  result.Number := 0;
end;

function MakeBoolean(const value : TTriState) : TValue;
begin
  result.Kind := vkBoolean;
  result.Bool := value;
  result.Number := 0;
end;

function MakeNumber(const value : double) : TValue;
begin
  result.Kind := vkNumber;
  result.Bool := tsUnknown;
  result.Number := value;
end;

{ TValue }

function TValue.AsTriState : TTriState;
begin
  if Kind = vkBoolean then
    result := Bool
  else
    // a number is not a condition, and an unknown thing tells us nothing.
    result := tsUnknown;
end;

{ tokenizer }

function Tokenize(const expression : string; out tokens : TArray<TToken>) : boolean;
var
  scan : integer;
  len : integer;
  start : integer;
  count : integer;
  text : string;
  formatSettings : TFormatSettings;

  procedure AddToken(const kind : TTokenKind; const tokenText : string; const number : double);
  begin
    if count = Length(tokens) then
      SetLength(tokens, count + 16);
    tokens[count].Kind := kind;
    tokens[count].Text := tokenText;
    tokens[count].Number := number;
    Inc(count);
  end;

begin
  tokens := nil;
  count := 0;
  formatSettings := TFormatSettings.Invariant;
  scan := 1;
  len := Length(expression);

  while scan <= len do
  begin
    if expression[scan].IsWhiteSpace then
    begin
      Inc(scan);
      Continue;
    end;

    if expression[scan].IsLetter or (expression[scan] = '_') then
    begin
      start := scan;
      while (scan <= len) and (expression[scan].IsLetterOrDigit or (expression[scan] = '_')) do
        Inc(scan);
      AddToken(tkIdentifier, Copy(expression, start, scan - start), 0);
      Continue;
    end;

    if expression[scan].IsDigit then
    begin
      start := scan;
      while (scan <= len) and expression[scan].IsDigit do
        Inc(scan);
      // one optional fractional part, so that 36.0 works but 36.0.1 does not
      if (scan < len) and (expression[scan] = '.') and expression[scan + 1].IsDigit then
      begin
        Inc(scan);
        while (scan <= len) and expression[scan].IsDigit do
          Inc(scan);
      end;
      text := Copy(expression, start, scan - start);
      AddToken(tkNumber, text, StrToFloat(text, formatSettings));
      Continue;
    end;

    case expression[scan] of
      '(' :
        begin
          AddToken(tkLParen, '(', 0);
          Inc(scan);
        end;
      ')' :
        begin
          AddToken(tkRParen, ')', 0);
          Inc(scan);
        end;
      '=' :
        begin
          AddToken(tkEqual, '=', 0);
          Inc(scan);
        end;
      '<' :
        begin
          if (scan < len) and (expression[scan + 1] = '=') then
          begin
            AddToken(tkLessEqual, '<=', 0);
            Inc(scan, 2);
          end
          else if (scan < len) and (expression[scan + 1] = '>') then
          begin
            AddToken(tkNotEqual, '<>', 0);
            Inc(scan, 2);
          end
          else
          begin
            AddToken(tkLess, '<', 0);
            Inc(scan);
          end;
        end;
      '>' :
        begin
          if (scan < len) and (expression[scan + 1] = '=') then
          begin
            AddToken(tkGreaterEqual, '>=', 0);
            Inc(scan, 2);
          end
          else
          begin
            AddToken(tkGreater, '>', 0);
            Inc(scan);
          end;
        end;
    else
      // Something we do not understand at all. Bail out rather than silently skipping
      // it, because skipping could turn a meaningful expression into a wrong answer.
      Exit(false);
    end;
  end;

  SetLength(tokens, count + 1);
  tokens[count].Kind := tkEnd;
  tokens[count].Text := '';
  tokens[count].Number := 0;
  result := true;
end;

{ TParser }

constructor TParser.Create(const tokens : TArray<TToken>; const defines : IDefineSet);
begin
  inherited Create;
  FTokens := tokens;
  FDefines := defines;
  FIndex := 0;
  FFailed := false;
end;

function TParser.Current : TToken;
begin
  result := FTokens[FIndex];
end;

procedure TParser.Advance;
begin
  if FTokens[FIndex].Kind <> tkEnd then
    Inc(FIndex);
end;

function TParser.CurrentIsKeyword(const keyword : string) : boolean;
begin
  result := (Current.Kind = tkIdentifier) and SameText(Current.Text, keyword);
end;

procedure TParser.Fail;
begin
  FFailed := true;
end;

function TParser.Parse : TTriState;
var
  value : TValue;
begin
  value := ParseExpression;
  // anything left over means we did not understand the shape of the expression
  if FFailed or (Current.Kind <> tkEnd) then
    result := tsUnknown
  else
    result := value.AsTriState;
end;

function TParser.ParseExpression : TValue;
begin
  result := ParseOr;
end;

function TParser.ParseOr : TValue;
var
  right : TValue;
  combined : TTriState;
begin
  result := ParseAnd;
  while (not FFailed) and CurrentIsKeyword('or') do
  begin
    Advance;
    right := ParseAnd;
    combined := TriStateOr(result.AsTriState, right.AsTriState);
    result := MakeBoolean(combined);
  end;
end;

function TParser.ParseAnd : TValue;
var
  right : TValue;
  combined : TTriState;
begin
  result := ParseNot;
  while (not FFailed) and CurrentIsKeyword('and') do
  begin
    Advance;
    right := ParseNot;
    combined := TriStateAnd(result.AsTriState, right.AsTriState);
    result := MakeBoolean(combined);
  end;
end;

function TParser.ParseNot : TValue;
begin
  if CurrentIsKeyword('not') then
  begin
    Advance;
    result := MakeBoolean(TriStateNot(ParseNot.AsTriState));
  end
  else
    result := ParseComparison;
end;

function TParser.ParseComparison : TValue;
var
  left : TValue;
  right : TValue;
  operation : TTokenKind;
begin
  left := ParsePrimary;
  if FFailed then
    Exit(MakeUnknown);

  if not (Current.Kind in [tkEqual, tkNotEqual, tkLess, tkLessEqual, tkGreater, tkGreaterEqual]) then
    Exit(left);

  operation := Current.Kind;
  Advance;
  right := ParsePrimary;
  if FFailed then
    Exit(MakeUnknown);

  // We can only compare things we actually have values for.
  if (left.Kind <> vkNumber) or (right.Kind <> vkNumber) then
    Exit(MakeBoolean(tsUnknown));

  case operation of
    tkEqual        : result := MakeBoolean(BooleanToTriState(SameValue(left.Number, right.Number)));
    tkNotEqual     : result := MakeBoolean(BooleanToTriState(not SameValue(left.Number, right.Number)));
    tkLess         : result := MakeBoolean(BooleanToTriState(left.Number < right.Number));
    tkLessEqual    : result := MakeBoolean(BooleanToTriState(left.Number <= right.Number));
    tkGreater      : result := MakeBoolean(BooleanToTriState(left.Number > right.Number));
    tkGreaterEqual : result := MakeBoolean(BooleanToTriState(left.Number >= right.Number));
  else
    result := MakeBoolean(tsUnknown);
  end;
end;

function TParser.ParseCallArgument(out argument : string) : boolean;
begin
  argument := '';
  if Current.Kind <> tkLParen then
    Exit(false);
  Advance;
  if Current.Kind <> tkIdentifier then
    Exit(false);
  argument := Current.Text;
  Advance;
  if Current.Kind <> tkRParen then
    Exit(false);
  Advance;
  result := true;
end;

function TParser.ParsePrimary : TValue;
var
  name : string;
  argument : string;
  numeric : double;
begin
  case Current.Kind of
    tkNumber :
      begin
        result := MakeNumber(Current.Number);
        Advance;
      end;

    tkLParen :
      begin
        Advance;
        result := ParseExpression;
        if Current.Kind <> tkRParen then
        begin
          Fail;
          Exit(MakeUnknown);
        end;
        Advance;
      end;

    tkIdentifier :
      begin
        name := Current.Text;

        if SameText(name, 'True') then
        begin
          Advance;
          Exit(MakeBoolean(tsTrue));
        end;

        if SameText(name, 'False') then
        begin
          Advance;
          Exit(MakeBoolean(tsFalse));
        end;

        if SameText(name, 'Defined') then
        begin
          Advance;
          if not ParseCallArgument(argument) then
          begin
            Fail;
            Exit(MakeUnknown);
          end;
          if FDefines.IsDefined(argument) then
            Exit(MakeBoolean(tsTrue));
          Exit(MakeBoolean(tsFalse));
        end;

        if SameText(name, 'Declared') then
        begin
          Advance;
          if not ParseCallArgument(argument) then
          begin
            Fail;
            Exit(MakeUnknown);
          end;
          // Declared() asks about identifiers in the compiled program, which we never
          // see. Honest answer: we do not know.
          Exit(MakeBoolean(tsUnknown));
        end;

        Advance;
        if FDefines.TryGetNumeric(name, numeric) then
          Exit(MakeNumber(numeric));

        // Some other identifier - possibly a boolean constant. We cannot know.
        result := MakeUnknown;
      end;
  else
    Fail;
    result := MakeUnknown;
  end;
end;

{ TConditionalEvaluator }

class function TConditionalEvaluator.Evaluate(const expression : string; const defines : IDefineSet) : TTriState;
var
  tokens : TArray<TToken>;
  parser : TParser;
begin
  if Trim(expression) = '' then
    Exit(tsUnknown);

  if not Tokenize(expression, tokens) then
    Exit(tsUnknown);

  parser := TParser.Create(tokens, defines);
  try
    result := parser.Parse;
  finally
    parser.Free;
  end;
end;

end.
