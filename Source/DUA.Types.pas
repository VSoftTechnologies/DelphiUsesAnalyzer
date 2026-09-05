unit DUA.Types;

interface

type
  /// <summary>
  ///   Three valued logic used when evaluating conditional expressions. Delphi's own
  ///   preprocessor only has true and false, but we cannot always know - for example
  ///   {$IF Declared(Foo)} depends on symbols we never see. Unknown lets us say so
  ///   rather than guessing.
  /// </summary>
  TTriState = (tsFalse, tsTrue, tsUnknown);

  /// <summary>
  ///   Where a unit was found. This becomes the node "source" in the json output and
  ///   controls whether the walk descends into the unit.
  /// </summary>
  TUnitKind = (
    ukProgram,      // the dpr itself
    ukProject,      // named in the dpr uses clause, or found on a project search path
    ukPackage,      // found under a dpm package path
    ukLibrary,      // found on the IDE library path, but not part of Delphi itself
    ukRTL,          // found under the Delphi installation
    ukUnresolved    // not found at all
  );

  /// <summary>Which uses clause an edge came from.</summary>
  TUsesSection = (usProgram, usInterface, usImplementation);

  /// <summary>
  ///   How much we trust an edge. Conditional means it is real but guarded by a
  ///   directive we evaluated. Unevaluated means we could not evaluate the guard and
  ///   took every branch, so the edge may not exist in a real compile.
  /// </summary>
  TEdgeCertainty = (ecUnconditional, ecConditional, ecUnevaluated);

  /// <summary>One entry in a uses clause, as written.</summary>
  TUsesEntry = record
    /// <summary>The name exactly as written, which may be unqualified.</summary>
    UnitName : string;
    /// <summary>The path from `in '...'`, only ever present in a dpr or dpk.</summary>
    InPath : string;
    Section : TUsesSection;
    Certainty : TEdgeCertainty;
    /// <summary>The enclosing directives, outermost first, empty when unconditional.</summary>
    Condition : string;
    /// <summary>The file it was written in, which may be an include rather than the unit.</summary>
    FileName : string;
    Line : integer;
  end;

  /// <summary>Something we could not work out while scanning. Always reported, never fatal.</summary>
  TScanWarning = record
    FileName : string;
    Line : integer;
    Message : string;
  end;

function BooleanToTriState(const value : boolean) : TTriState;
function TriStateAnd(const left, right : TTriState) : TTriState;
function TriStateOr(const left, right : TTriState) : TTriState;
function TriStateNot(const value : TTriState) : TTriState;

/// <summary>
///   Case insensitive glob against a unit name. * matches any run of characters and ?
///   matches exactly one. A pattern with no wildcard has to match the whole name, so
///   asking for Forms does not quietly also answer for Vcl.Forms.
/// </summary>
function MatchesUnitPattern(const pattern : string; const value : string) : boolean;
function IsWildcardPattern(const pattern : string) : boolean;

function UsesSectionToString(const value : TUsesSection) : string;
function EdgeCertaintyToString(const value : TEdgeCertainty) : string;
function UnitKindToString(const value : TUnitKind) : string;

implementation

uses
  System.SysUtils;

function BooleanToTriState(const value : boolean) : TTriState;
begin
  if value then
    result := tsTrue
  else
    result := tsFalse;
end;

function TriStateAnd(const left, right : TTriState) : TTriState;
begin
  // false wins over unknown - false and anything is false, even if we do not know
  // what the anything is.
  if (left = tsFalse) or (right = tsFalse) then
    result := tsFalse
  else if (left = tsUnknown) or (right = tsUnknown) then
    result := tsUnknown
  else
    result := tsTrue;
end;

function TriStateOr(const left, right : TTriState) : TTriState;
begin
  // true wins over unknown, for the same reason.
  if (left = tsTrue) or (right = tsTrue) then
    result := tsTrue
  else if (left = tsUnknown) or (right = tsUnknown) then
    result := tsUnknown
  else
    result := tsFalse;
end;

function TriStateNot(const value : TTriState) : TTriState;
begin
  case value of
    tsFalse : result := tsTrue;
    tsTrue : result := tsFalse;
  else
    result := tsUnknown;
  end;
end;

function IsWildcardPattern(const pattern : string) : boolean;
begin
  result := (Pos('*', pattern) > 0) or (Pos('?', pattern) > 0);
end;

function MatchesUnitPattern(const pattern : string; const value : string) : boolean;
var
  patternText : string;
  valueText : string;
  patternPos : integer;
  valuePos : integer;
  // where to resume from when a * turns out to have swallowed too little
  starPos : integer;
  starValuePos : integer;
begin
  if pattern = '' then
    Exit(false);

  // upper case once rather than per comparison
  patternText := UpperCase(pattern);
  valueText := UpperCase(value);

  patternPos := 1;
  valuePos := 1;
  starPos := 0;
  starValuePos := 0;

  while valuePos <= Length(valueText) do
  begin
    if (patternPos <= Length(patternText)) and
       ((patternText[patternPos] = '?') or (patternText[patternPos] = valueText[valuePos])) then
    begin
      Inc(patternPos);
      Inc(valuePos);
    end
    else if (patternPos <= Length(patternText)) and (patternText[patternPos] = '*') then
    begin
      // remember this star, and start by letting it match nothing at all
      starPos := patternPos;
      starValuePos := valuePos;
      Inc(patternPos);
    end
    else if starPos > 0 then
    begin
      // back up: the last star has to swallow one more character
      patternPos := starPos + 1;
      Inc(starValuePos);
      valuePos := starValuePos;
    end
    else
      Exit(false);
  end;

  // any stars left over match the empty remainder
  while (patternPos <= Length(patternText)) and (patternText[patternPos] = '*') do
    Inc(patternPos);

  result := patternPos > Length(patternText);
end;

function UsesSectionToString(const value : TUsesSection) : string;
begin
  case value of
    usProgram : result := 'program';
    usInterface : result := 'interface';
  else
    result := 'implementation';
  end;
end;

function EdgeCertaintyToString(const value : TEdgeCertainty) : string;
begin
  case value of
    ecUnconditional : result := 'unconditional';
    ecConditional : result := 'conditional';
  else
    result := 'unevaluated';
  end;
end;

function UnitKindToString(const value : TUnitKind) : string;
begin
  case value of
    ukProgram : result := 'program';
    ukProject : result := 'project';
    ukPackage : result := 'package';
    ukLibrary : result := 'library';
    ukRTL : result := 'rtl';
  else
    result := 'unresolved';
  end;
end;

end.
