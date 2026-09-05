unit DUA.Project.MSBuild;

interface

uses
  Spring.Collections;

type
  /// <summary>
  ///   The set of msbuild properties in effect. Names are case insensitive, as they are
  ///   in msbuild itself.
  /// </summary>
  IMSBuildProperties = interface
    ['{1B4E9F27-8A3C-4D6E-B0F5-7C2A9E1D4B38}']
    procedure SetValue(const name : string; const value : string);
    function TryGetValue(const name : string; out value : string) : boolean;
    /// <summary>Empty string when the property is not set, which is what msbuild does.</summary>
    function GetValue(const name : string) : string;
    function Contains(const name : string) : boolean;
    function Names : TArray<string>;
  end;

  TMSBuildProperties = class(TInterfacedObject, IMSBuildProperties)
  private
    FValues : IDictionary<string, string>;
    FOriginalNames : IDictionary<string, string>;
  protected
    procedure SetValue(const name : string; const value : string);
    function TryGetValue(const name : string; out value : string) : boolean;
    function GetValue(const name : string) : string;
    function Contains(const name : string) : boolean;
    function Names : TArray<string>;
  public
    constructor Create;
  end;

  TMSBuild = record
  public
    /// <summary>
    ///   Expand $(Name) references. An unset property expands to an empty string, which
    ///   is how msbuild behaves and is what makes the $(DCC_UnitSearchPath) self
    ///   reference idiom work on the first group that uses it. Falls back to environment
    ///   variables, so $(APPDATA) resolves the way dpm expects.
    /// </summary>
    class function Expand(const value : string; const properties : IMSBuildProperties) : string; static;

    /// <summary>
    ///   Evaluate a Condition attribute. Supports the forms real dproj files use:
    ///   equality and inequality of quoted operands, combined with and/or and grouped
    ///   with parentheses. Anything else evaluates to false rather than guessing.
    /// </summary>
    class function EvaluateCondition(const condition : string; const properties : IMSBuildProperties) : boolean; static;
  end;

implementation

uses
  System.Character,
  System.StrUtils,
  System.SysUtils;

const
  Quote = '''';

type
  TConditionTokenKind = (ctEnd, ctLiteral, ctEqual, ctNotEqual, ctAnd, ctOr, ctLParen, ctRParen);

  TConditionToken = record
    Kind : TConditionTokenKind;
    Text : string;
  end;

  TConditionParser = class
  private
    FTokens : TArray<TConditionToken>;
    FIndex : integer;
    FFailed : boolean;
    function Current : TConditionToken;
    procedure Advance;
    function ParseOr : boolean;
    function ParseAnd : boolean;
    function ParsePrimary : boolean;
  public
    constructor Create(const tokens : TArray<TConditionToken>);
    function Parse(out value : boolean) : boolean;
  end;

{ TMSBuildProperties }

constructor TMSBuildProperties.Create;
begin
  inherited Create;
  FValues := TCollections.CreateDictionary<string, string>;
  FOriginalNames := TCollections.CreateDictionary<string, string>;
end;

procedure TMSBuildProperties.SetValue(const name : string; const value : string);
begin
  if name = '' then
    Exit;
  FValues[UpperCase(name)] := value;
  FOriginalNames[UpperCase(name)] := name;
end;

function TMSBuildProperties.TryGetValue(const name : string; out value : string) : boolean;
begin
  result := FValues.TryGetValue(UpperCase(name), value);
  if not result then
    value := '';
end;

function TMSBuildProperties.GetValue(const name : string) : string;
begin
  if not TryGetValue(name, result) then
    result := '';
end;

function TMSBuildProperties.Contains(const name : string) : boolean;
begin
  result := FValues.ContainsKey(UpperCase(name));
end;

function TMSBuildProperties.Names : TArray<string>;
begin
  result := FOriginalNames.Values.ToArray;
end;

{ TMSBuild }

class function TMSBuild.Expand(const value : string; const properties : IMSBuildProperties) : string;
var
  scan : integer;
  len : integer;
  closing : integer;
  name : string;
  replacement : string;
begin
  result := '';
  scan := 1;
  len := Length(value);

  while scan <= len do
  begin
    if (value[scan] = '$') and (scan < len) and (value[scan + 1] = '(') then
    begin
      closing := PosEx(')', value, scan + 2);
      if closing = 0 then
      begin
        // no closing paren, so this is not a reference - take the rest as written
        result := result + Copy(value, scan, MaxInt);
        Exit;
      end;

      name := Copy(value, scan + 2, closing - scan - 2);
      if not properties.TryGetValue(name, replacement) then
        // msbuild treats environment variables as properties, which is how the
        // $(APPDATA) in a dpm cache path resolves
        replacement := GetEnvironmentVariable(name);
      result := result + replacement;
      scan := closing + 1;
      Continue;
    end;

    result := result + value[scan];
    Inc(scan);
  end;
end;

function TokenizeCondition(const condition : string; out tokens : TArray<TConditionToken>) : boolean;
var
  scan : integer;
  len : integer;
  start : integer;
  count : integer;
  word : string;

  procedure AddToken(const kind : TConditionTokenKind; const text : string);
  begin
    if count = Length(tokens) then
      SetLength(tokens, count + 8);
    tokens[count].Kind := kind;
    tokens[count].Text := text;
    Inc(count);
  end;

begin
  tokens := nil;
  count := 0;
  scan := 1;
  len := Length(condition);

  while scan <= len do
  begin
    if condition[scan].IsWhiteSpace then
    begin
      Inc(scan);
      Continue;
    end;

    if condition[scan] = Quote then
    begin
      Inc(scan);
      start := scan;
      while (scan <= len) and (condition[scan] <> Quote) do
        Inc(scan);
      if scan > len then
        Exit(false); // unterminated literal
      AddToken(ctLiteral, Copy(condition, start, scan - start));
      Inc(scan);
      Continue;
    end;

    if (condition[scan] = '=') and (scan < len) and (condition[scan + 1] = '=') then
    begin
      AddToken(ctEqual, '==');
      Inc(scan, 2);
      Continue;
    end;

    if (condition[scan] = '!') and (scan < len) and (condition[scan + 1] = '=') then
    begin
      AddToken(ctNotEqual, '!=');
      Inc(scan, 2);
      Continue;
    end;

    if condition[scan] = '(' then
    begin
      AddToken(ctLParen, '(');
      Inc(scan);
      Continue;
    end;

    if condition[scan] = ')' then
    begin
      AddToken(ctRParen, ')');
      Inc(scan);
      Continue;
    end;

    if condition[scan].IsLetter then
    begin
      start := scan;
      while (scan <= len) and condition[scan].IsLetterOrDigit do
        Inc(scan);
      word := Copy(condition, start, scan - start);
      if SameText(word, 'and') then
        AddToken(ctAnd, 'and')
      else if SameText(word, 'or') then
        AddToken(ctOr, 'or')
      else
        // a bare word is a function or comparison we do not model, such as Exists()
        Exit(false);
      Continue;
    end;

    Exit(false);
  end;

  SetLength(tokens, count + 1);
  tokens[count].Kind := ctEnd;
  tokens[count].Text := '';
  result := true;
end;

{ TConditionParser }

constructor TConditionParser.Create(const tokens : TArray<TConditionToken>);
begin
  inherited Create;
  FTokens := tokens;
  FIndex := 0;
  FFailed := false;
end;

function TConditionParser.Current : TConditionToken;
begin
  result := FTokens[FIndex];
end;

procedure TConditionParser.Advance;
begin
  if FTokens[FIndex].Kind <> ctEnd then
    Inc(FIndex);
end;

function TConditionParser.Parse(out value : boolean) : boolean;
begin
  value := ParseOr;
  // leftover tokens mean we misread the shape, so refuse the whole condition
  result := (not FFailed) and (Current.Kind = ctEnd);
end;

function TConditionParser.ParseOr : boolean;
var
  right : boolean;
begin
  result := ParseAnd;
  while (not FFailed) and (Current.Kind = ctOr) do
  begin
    Advance;
    right := ParseAnd;
    result := result or right;
  end;
end;

function TConditionParser.ParseAnd : boolean;
var
  right : boolean;
begin
  result := ParsePrimary;
  while (not FFailed) and (Current.Kind = ctAnd) do
  begin
    Advance;
    right := ParsePrimary;
    result := result and right;
  end;
end;

function TConditionParser.ParsePrimary : boolean;
var
  left : string;
  right : string;
  operation : TConditionTokenKind;
begin
  result := false;

  if Current.Kind = ctLParen then
  begin
    Advance;
    result := ParseOr;
    if Current.Kind <> ctRParen then
    begin
      FFailed := true;
      Exit(false);
    end;
    Advance;
    Exit;
  end;

  if Current.Kind <> ctLiteral then
  begin
    FFailed := true;
    Exit(false);
  end;

  left := Current.Text;
  Advance;

  if not (Current.Kind in [ctEqual, ctNotEqual]) then
  begin
    FFailed := true;
    Exit(false);
  end;

  operation := Current.Kind;
  Advance;

  if Current.Kind <> ctLiteral then
  begin
    FFailed := true;
    Exit(false);
  end;

  right := Current.Text;
  Advance;

  // msbuild compares strings case insensitively, which matters because a dproj writes
  // Base as "True" in one group and tests it against "true" in the next
  if operation = ctEqual then
    result := SameText(left, right)
  else
    result := not SameText(left, right);
end;

class function TMSBuild.EvaluateCondition(const condition : string; const properties : IMSBuildProperties) : boolean;
var
  tokens : TArray<TConditionToken>;
  parser : TConditionParser;
begin
  // an element or group with no Condition always applies
  if Trim(condition) = '' then
    Exit(true);

  // msbuild expands properties before evaluating, so by the time we parse we are only
  // ever comparing literals
  if not TokenizeCondition(TMSBuild.Expand(condition, properties), tokens) then
    Exit(false);

  parser := TConditionParser.Create(tokens);
  try
    if not parser.Parse(result) then
      result := false;
  finally
    parser.Free;
  end;
end;

end.
