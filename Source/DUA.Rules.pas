unit DUA.Rules;

{
  The rules the check command enforces: which units a project is not allowed to reach.

  A rule file is one glob per line, in the shape gitignore made familiar - a bare pattern
  forbids, a ! in front of one carves an exception back out, and # or // starts a comment.
  There is deliberately no syntax for anything else. A rule that needed explaining would
  be a rule nobody puts in their build.

    # no gui in the service
    Vcl.*
    Fmx.*
    !Vcl.Graphics      # the printer code needs TCanvas
}

interface

uses
  System.SysUtils,
  Spring.Collections;

type
  TUnitRule = record
    /// <summary>An exception to the forbidding rules rather than one of them.</summary>
    Allow : boolean;
    Pattern : string;
    /// <summary>Where it was written, or 0 when it came from a switch.</summary>
    Line : integer;
  end;

  IRuleSet = interface
    ['{9E4B1D06-3F72-4A85-B0C9-5D8617AE243F}']
    function GetRules : IReadOnlyList<TUnitRule>;
    /// <summary>Rules that forbid something. A set of nothing but exceptions forbids nothing.</summary>
    function ForbidCount : integer;
    /// <summary>The forbidding pattern this unit breaks, or empty when it is fine.</summary>
    function ViolatedBy(const unitName : string) : string;
    /// <summary>
    ///   The same question for a unit known by more than one name. A unit is judged by
    ///   every name it goes by, so a rule written against the name in the source catches
    ///   it even when the compiler resolved it to something longer.
    /// </summary>
    function ViolatedByAny(const names : TArray<string>) : string;
    /// <summary>
    ///   Whether an exception covers this unit. Reporting rule by rule needs to ask each
    ///   forbidding rule on its own, and every one of them still loses to an exception.
    /// </summary>
    function Excused(const names : TArray<string>) : boolean;
    property Rules : IReadOnlyList<TUnitRule> read GetRules;
  end;

  ERulesError = class(Exception);

  TRules = record
  public
    /// <summary>
    ///   Reads rule lines. source names where they came from, so an error can say which
    ///   file and line to go and look at.
    /// </summary>
    class function Parse(const lines : TArray<string>; const source : string) : IRuleSet; static;
    class function LoadFromFile(const fileName : string) : IRuleSet; static;
    /// <summary>Rules given on the command line, which carry no line number.</summary>
    class function FromSwitches(const forbid : TArray<string>;
                                const allow : TArray<string>) : IRuleSet; static;
    /// <summary>
    ///   Both sets together. Order does not matter - a unit is in trouble when something
    ///   forbids it and nothing allows it, wherever either rule was written.
    /// </summary>
    class function Combine(const left : IRuleSet; const right : IRuleSet) : IRuleSet; static;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  DUA.Types;

type
  TRuleSet = class(TInterfacedObject, IRuleSet)
  private
    FRules : IList<TUnitRule>;
  protected
    function GetRules : IReadOnlyList<TUnitRule>;
    function ForbidCount : integer;
    function ViolatedBy(const unitName : string) : string;
    function ViolatedByAny(const names : TArray<string>) : string;
    function Excused(const names : TArray<string>) : boolean;
  public
    constructor Create;
    procedure Add(const rule : TUnitRule);
  end;

constructor TRuleSet.Create;
begin
  inherited Create;
  FRules := TCollections.CreateList<TUnitRule>;
end;

procedure TRuleSet.Add(const rule : TUnitRule);
begin
  FRules.Add(rule);
end;

function TRuleSet.GetRules : IReadOnlyList<TUnitRule>;
begin
  result := FRules.AsReadOnly;
end;

function TRuleSet.ForbidCount : integer;
var
  rule : TUnitRule;
begin
  result := 0;
  for rule in FRules do
    if not rule.Allow then
      Inc(result);
end;

function TRuleSet.Excused(const names : TArray<string>) : boolean;
var
  rule : TUnitRule;
  name : string;
begin
  for rule in FRules do
    if rule.Allow then
      for name in names do
        if MatchesUnitPattern(rule.Pattern, name) then
          Exit(true);
  result := false;
end;

function TRuleSet.ViolatedByAny(const names : TArray<string>) : string;
var
  rule : TUnitRule;
  name : string;
begin
  result := '';
  // an exception beats every rule it is an exception to, so it is settled first
  if Excused(names) then
    Exit;

  for rule in FRules do
    if not rule.Allow then
      for name in names do
        if MatchesUnitPattern(rule.Pattern, name) then
          Exit(rule.Pattern);
end;

function TRuleSet.ViolatedBy(const unitName : string) : string;
begin
  result := ViolatedByAny(TArray<string>.Create(unitName));
end;

{ TRules }

/// <summary>
///   Everything from the first # or // onwards. Neither can appear in a unit name, so
///   there is nothing to be careful about.
/// </summary>
function WithoutComment(const line : string) : string;
var
  hash : integer;
  slashes : integer;
  cut : integer;
begin
  hash := Pos('#', line);
  slashes := Pos('//', line);

  cut := hash;
  if (slashes > 0) and ((cut = 0) or (slashes < cut)) then
    cut := slashes;

  if cut > 0 then
    result := Copy(line, 1, cut - 1)
  else
    result := line;
end;

function RuleFrom(const line : string; const number : integer;
  const source : string) : TUnitRule;
var
  text : string;
begin
  result := Default(TUnitRule);
  result.Line := number;

  text := Trim(WithoutComment(line));
  result.Allow := StartsStr('!', text);
  if result.Allow then
    text := Trim(Copy(text, 2, MaxInt));

  if text = '' then
    raise ERulesError.CreateFmt('%s(%d): a rule needs a unit name or a glob after the !',
      [source, number]);

  // One rule per line is the whole grammar, so a space in the middle is someone writing
  // in a syntax this does not have - saying so is more use than silently never matching.
  if Pos(' ', text) > 0 then
    raise ERulesError.CreateFmt(
      '%s(%d): "%s" looks like more than one rule. Write one unit name or glob per line, ' +
      'and put ! in front of a line to allow it', [source, number, text]);

  result.Pattern := text;
end;

class function TRules.Parse(const lines : TArray<string>; const source : string) : IRuleSet;
var
  parsed : TRuleSet;
  index : integer;
begin
  parsed := TRuleSet.Create;
  result := parsed;

  for index := 0 to High(lines) do
    if Trim(WithoutComment(lines[index])) <> '' then
      parsed.Add(RuleFrom(lines[index], index + 1, source));
end;

class function TRules.LoadFromFile(const fileName : string) : IRuleSet;
begin
  if not TFile.Exists(fileName) then
    raise ERulesError.CreateFmt('rules file not found: %s', [fileName]);

  result := Parse(TFile.ReadAllLines(fileName), ExtractFileName(fileName));
end;

class function TRules.FromSwitches(const forbid : TArray<string>;
  const allow : TArray<string>) : IRuleSet;
var
  built : TRuleSet;
  rule : TUnitRule;
  pattern : string;
begin
  built := TRuleSet.Create;
  result := built;

  for pattern in forbid do
    if Trim(pattern) <> '' then
    begin
      rule := Default(TUnitRule);
      rule.Pattern := Trim(pattern);
      built.Add(rule);
    end;

  for pattern in allow do
    if Trim(pattern) <> '' then
    begin
      rule := Default(TUnitRule);
      rule.Allow := true;
      rule.Pattern := Trim(pattern);
      built.Add(rule);
    end;
end;

class function TRules.Combine(const left : IRuleSet; const right : IRuleSet) : IRuleSet;
var
  built : TRuleSet;
  rule : TUnitRule;
begin
  built := TRuleSet.Create;
  result := built;

  if left <> nil then
    for rule in left.Rules do
      built.Add(rule);
  if right <> nil then
    for rule in right.Rules do
      built.Add(rule);
end;

end.
