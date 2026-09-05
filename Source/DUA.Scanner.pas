unit DUA.Scanner;

interface

uses
  Spring.Collections,
  DUA.Types,
  DUA.Defines;

type
  /// <summary>
  ///   Supplies the content of a {$I} include file. The scanner never touches the file
  ///   system itself, which keeps it testable and lets the real resolver apply the
  ///   project search paths.
  /// </summary>
  IIncludeResolver = interface
    ['{2C6E6F5B-9E4A-4C1D-8E7F-6B1D0A3C9E52}']
    /// <summary>
    ///   Resolve includeName as written in the directive, relative to parentFileName.
    ///   Returns false when it cannot be found, in which case the scanner warns.
    /// </summary>
    function TryResolve(const parentFileName : string; const includeName : string;
                        out resolvedFileName : string; out content : string) : boolean;
  end;

  IScanResult = interface
    ['{6F1B8C1E-3A5D-4B2E-9C7A-1D8E4F2B6A03}']
    function GetUnitName : string;
    function GetIsProgram : boolean;
    function GetEntries : IReadOnlyList<TUsesEntry>;
    function GetWarnings : IReadOnlyList<TScanWarning>;
    function GetIncludedFiles : IReadOnlyList<string>;

    /// <summary>The name from the unit/program/library header.</summary>
    property UnitName : string read GetUnitName;
    /// <summary>True for a dpr or dpk, which has one uses clause rather than two.</summary>
    property IsProgram : boolean read GetIsProgram;
    property Entries : IReadOnlyList<TUsesEntry> read GetEntries;
    property Warnings : IReadOnlyList<TScanWarning> read GetWarnings;
    property IncludedFiles : IReadOnlyList<string> read GetIncludedFiles;
  end;

  IUnitScanner = interface
    ['{9D3A7E42-5C8B-4F1A-B6D9-2E0C7A4B8F16}']
    /// <summary>
    ///   Scan Delphi source. The define set is cloned, so {$DEFINE} in the source cannot
    ///   leak out to the next unit scanned - which is how the compiler behaves.
    /// </summary>
    function Scan(const source : string; const fileName : string;
                  const defines : IDefineSet) : IScanResult;
  end;

  TUnitScanner = class(TInterfacedObject, IUnitScanner)
  private type
    /// <summary>
    ///   One level of {$IFDEF}/{$IF} nesting. PriorAggregate is the OR of every branch
    ///   condition seen so far in this if/elseif/else chain, which is what lets {$ELSE}
    ///   mean "none of the above" even when some of the above were unknown.
    /// </summary>
    TConditionalFrame = record
      DisplayText : string;
      ChainText : string;
      BranchState : TTriState;
      PriorAggregate : TTriState;
      /// <summary>
      ///   Held back until something in this region is actually collected. Most
      ///   conditionals in real source guard declarations, not uses clauses, and
      ///   warning about those buries the ones that matter.
      /// </summary>
      PendingWarning : string;
      WarningFile : string;
      WarningLine : integer;
      Reported : boolean;
    end;
  private
    FIncludeResolver : IIncludeResolver;

    // per scan state
    FEntries : IList<TUsesEntry>;
    FWarnings : IList<TScanWarning>;
    FIncludedFiles : IList<string>;
    FDefines : IDefineSet;
    FFrames : IList<TConditionalFrame>;
    FIncludeStack : IList<string>;
    FUnitName : string;
    FIsProgram : boolean;
    FSeenHeader : boolean;
    FExpectingHeaderName : boolean;
    FSeenImplementation : boolean;

    // uses clause state - deliberately not per buffer, because an include can be
    // opened in the middle of a uses clause and contribute entries to it.
    FInUses : boolean;
    FExpectingInPath : boolean;
    FPendingName : string;
    FPendingInPath : string;
    FPendingFile : string;
    FPendingLine : integer;
    FPendingSection : TUsesSection;
    FPendingCertainty : TEdgeCertainty;
    FPendingCondition : string;

    function IsActive : boolean;
    function CurrentCertainty : TEdgeCertainty;
    function CurrentCondition : string;
    procedure Warn(const fileName : string; const line : integer; const message : string);
    procedure ReportGuardWarnings;
    procedure FlushPendingEntry;
    procedure HandleIdentifier(const identifier : string; const fileName : string; const line : integer);
    procedure HandleDirective(const body : string; const fileName : string; const line : integer);
    procedure HandleInclude(const parameter : string; const fileName : string; const line : integer);
    procedure ScanBuffer(const source : string; const fileName : string);
    procedure Reset(const defines : IDefineSet);
  protected
    function Scan(const source : string; const fileName : string;
                  const defines : IDefineSet) : IScanResult;
  public
    constructor Create(const includeResolver : IIncludeResolver = nil);
  end;

implementation

uses
  System.Character,
  System.SysUtils,
  DUA.Conditionals;

type
  TScanResult = class(TInterfacedObject, IScanResult)
  private
    FUnitName : string;
    FIsProgram : boolean;
    FEntries : IList<TUsesEntry>;
    FWarnings : IList<TScanWarning>;
    FIncludedFiles : IList<string>;
  protected
    function GetUnitName : string;
    function GetIsProgram : boolean;
    function GetEntries : IReadOnlyList<TUsesEntry>;
    function GetWarnings : IReadOnlyList<TScanWarning>;
    function GetIncludedFiles : IReadOnlyList<string>;
  public
    constructor Create(const unitName : string; const isProgram : boolean;
                       const entries : IList<TUsesEntry>; const warnings : IList<TScanWarning>;
                       const includedFiles : IList<string>);
  end;

{ TScanResult }

constructor TScanResult.Create(const unitName : string; const isProgram : boolean;
  const entries : IList<TUsesEntry>; const warnings : IList<TScanWarning>;
  const includedFiles : IList<string>);
begin
  inherited Create;
  FUnitName := unitName;
  FIsProgram := isProgram;
  FEntries := entries;
  FWarnings := warnings;
  FIncludedFiles := includedFiles;
end;

function TScanResult.GetUnitName : string;
begin
  result := FUnitName;
end;

function TScanResult.GetIsProgram : boolean;
begin
  result := FIsProgram;
end;

function TScanResult.GetEntries : IReadOnlyList<TUsesEntry>;
begin
  result := FEntries.AsReadOnly;
end;

function TScanResult.GetWarnings : IReadOnlyList<TScanWarning>;
begin
  result := FWarnings.AsReadOnly;
end;

function TScanResult.GetIncludedFiles : IReadOnlyList<string>;
begin
  result := FIncludedFiles.AsReadOnly;
end;

{ TUnitScanner }

constructor TUnitScanner.Create(const includeResolver : IIncludeResolver);
begin
  inherited Create;
  FIncludeResolver := includeResolver;
end;

procedure TUnitScanner.Reset(const defines : IDefineSet);
begin
  FEntries := TCollections.CreateList<TUsesEntry>;
  FWarnings := TCollections.CreateList<TScanWarning>;
  FIncludedFiles := TCollections.CreateList<string>;
  FFrames := TCollections.CreateList<TConditionalFrame>;
  FIncludeStack := TCollections.CreateList<string>;
  // clone, so {$DEFINE} in this unit cannot leak into the next one we scan
  FDefines := defines.Clone;
  FUnitName := '';
  FIsProgram := false;
  FSeenHeader := false;
  FExpectingHeaderName := false;
  FSeenImplementation := false;
  FInUses := false;
  FExpectingInPath := false;
  FPendingName := '';
  FPendingInPath := '';
  FPendingFile := '';
  FPendingLine := 0;
  FPendingSection := usInterface;
  FPendingCertainty := ecUnconditional;
  FPendingCondition := '';
end;

function TUnitScanner.Scan(const source : string; const fileName : string;
  const defines : IDefineSet) : IScanResult;
begin
  Reset(defines);
  ScanBuffer(source, fileName);

  // a clause left open at end of file, flush what we have rather than losing it
  FlushPendingEntry;

  if FFrames.Count > 0 then
    Warn(fileName, 0, Format('%d conditional directive(s) were never closed', [FFrames.Count]));

  result := TScanResult.Create(FUnitName, FIsProgram, FEntries, FWarnings, FIncludedFiles);
end;

function TUnitScanner.IsActive : boolean;
var
  frame : TConditionalFrame;
begin
  for frame in FFrames do
    if frame.BranchState = tsFalse then
      Exit(false);
  result := true;
end;

function TUnitScanner.CurrentCertainty : TEdgeCertainty;
var
  frame : TConditionalFrame;
begin
  if FFrames.Count = 0 then
    Exit(ecUnconditional);

  for frame in FFrames do
    if frame.BranchState = tsUnknown then
      Exit(ecUnevaluated);

  result := ecConditional;
end;

function TUnitScanner.CurrentCondition : string;
var
  frame : TConditionalFrame;
begin
  result := '';
  for frame in FFrames do
  begin
    if result <> '' then
      result := result + ' and ';
    result := result + frame.DisplayText;
  end;
end;

procedure TUnitScanner.Warn(const fileName : string; const line : integer; const message : string);
var
  warning : TScanWarning;
begin
  warning.FileName := fileName;
  warning.Line := line;
  warning.Message := message;
  FWarnings.Add(warning);
end;

procedure TUnitScanner.ReportGuardWarnings;
var
  index : integer;
  frame : TConditionalFrame;
begin
  // something inside these conditionals is going into the graph after all, so now the
  // directives guarding it are worth reporting - once each, however many units follow
  for index := 0 to FFrames.Count - 1 do
  begin
    frame := FFrames[index];
    if (frame.PendingWarning = '') or frame.Reported then
      Continue;
    Warn(frame.WarningFile, frame.WarningLine, frame.PendingWarning);
    frame.Reported := true;
    FFrames[index] := frame;
  end;
end;

procedure TUnitScanner.FlushPendingEntry;
var
  entry : TUsesEntry;
begin
  if FPendingName = '' then
    Exit;

  entry.UnitName := FPendingName;
  entry.InPath := FPendingInPath;
  entry.Section := FPendingSection;
  entry.Certainty := FPendingCertainty;
  entry.Condition := FPendingCondition;
  entry.FileName := FPendingFile;
  entry.Line := FPendingLine;
  FEntries.Add(entry);

  FPendingName := '';
  FPendingInPath := '';
  FExpectingInPath := false;
end;

procedure TUnitScanner.HandleIdentifier(const identifier : string; const fileName : string;
  const line : integer);
begin
  if not IsActive then
    Exit;

  if not FSeenHeader then
  begin
    if FExpectingHeaderName then
    begin
      FUnitName := identifier;
      FSeenHeader := true;
      FExpectingHeaderName := false;
      Exit;
    end;

    if SameText(identifier, 'unit') or SameText(identifier, 'program') or
       SameText(identifier, 'library') or SameText(identifier, 'package') then
    begin
      // a dpr, dpk or library has a single uses clause and no interface section
      FIsProgram := not SameText(identifier, 'unit');
      FExpectingHeaderName := true;
      Exit;
    end;
  end;

  if FInUses then
  begin
    if SameText(identifier, 'in') and (FPendingName <> '') then
    begin
      FExpectingInPath := true;
      Exit;
    end;

    // a new name means the previous one is complete
    FlushPendingEntry;
    FPendingName := identifier;
    FPendingFile := fileName;
    FPendingLine := line;
    if FIsProgram then
      FPendingSection := usProgram
    else if FSeenImplementation then
      FPendingSection := usImplementation
    else
      FPendingSection := usInterface;
    FPendingCertainty := CurrentCertainty;
    FPendingCondition := CurrentCondition;
    if FPendingCertainty = ecUnevaluated then
      ReportGuardWarnings;
    Exit;
  end;

  if SameText(identifier, 'implementation') then
  begin
    FSeenImplementation := true;
    Exit;
  end;

  if SameText(identifier, 'uses') then
  begin
    FInUses := true;
    FPendingName := '';
    FPendingInPath := '';
    FExpectingInPath := false;
  end;
end;

procedure TUnitScanner.HandleInclude(const parameter : string; const fileName : string;
  const line : integer);
var
  includeName : string;
  resolvedFileName : string;
  content : string;
  key : string;
begin
  includeName := Trim(parameter);

  // {$I+} / {$I-} is the io checking switch, not an include
  if (includeName = '') or CharInSet(includeName[1], ['+', '-']) then
    Exit;

  // {$I %DATE%} inlines a compiler value as a string literal, it reads no file
  if (Length(includeName) >= 2) and (includeName[1] = '%') and
     (includeName[Length(includeName)] = '%') then
    Exit;

  if (Length(includeName) >= 2) and (includeName[1] = '''') and
     (includeName[Length(includeName)] = '''') then
    includeName := Copy(includeName, 2, Length(includeName) - 2);

  if FIncludeResolver = nil then
  begin
    Warn(fileName, line, Format('cannot read include "%s", no include resolver', [includeName]));
    Exit;
  end;

  if not FIncludeResolver.TryResolve(fileName, includeName, resolvedFileName, content) then
  begin
    Warn(fileName, line, Format('include file not found: "%s"', [includeName]));
    Exit;
  end;

  key := LowerCase(resolvedFileName);
  if FIncludeStack.Contains(key) then
  begin
    Warn(fileName, line, Format('include cycle detected at "%s"', [includeName]));
    Exit;
  end;

  FIncludedFiles.Add(resolvedFileName);
  FIncludeStack.Add(key);
  try
    ScanBuffer(content, resolvedFileName);
  finally
    FIncludeStack.Remove(key);
  end;
end;

procedure TUnitScanner.HandleDirective(const body : string; const fileName : string;
  const line : integer);
var
  scan : integer;
  name : string;
  parameter : string;
  frame : TConditionalFrame;
  branch : TTriState;
  wasActive : boolean;
begin
  scan := 1;
  while (scan <= Length(body)) and body[scan].IsLetter do
    Inc(scan);
  name := Copy(body, 1, scan - 1);
  parameter := Trim(Copy(body, scan, MaxInt));

  // The enclosing region decides whether we even look at the condition. Evaluating a
  // directive inside dead code would produce warnings about code that never compiles.
  wasActive := IsActive;

  if SameText(name, 'IFDEF') or SameText(name, 'IFNDEF') or SameText(name, 'IF') or
     SameText(name, 'IFOPT') then
  begin
    if not wasActive then
      branch := tsFalse
    else if SameText(name, 'IFDEF') then
      branch := BooleanToTriState(FDefines.IsDefined(parameter))
    else if SameText(name, 'IFNDEF') then
      branch := TriStateNot(BooleanToTriState(FDefines.IsDefined(parameter)))
    else if SameText(name, 'IFOPT') then
      // Compiler switch state is not something we track, and it says nothing about what
      // a unit uses. Both branches are taken so no dependency is lost, but this is never
      // worth a warning.
      branch := tsUnknown
    else
      branch := TConditionalEvaluator.Evaluate(parameter, FDefines);

    frame.PendingWarning := '';
    frame.WarningFile := fileName;
    frame.WarningLine := line;
    frame.Reported := false;
    if (branch = tsUnknown) and SameText(name, 'IF') then
      frame.PendingWarning := Format('cannot evaluate {$IF %s}, taking every branch', [parameter]);

    frame.DisplayText := parameter;
    if SameText(name, 'IFNDEF') then
      frame.DisplayText := 'not ' + parameter;
    frame.ChainText := frame.DisplayText;
    frame.BranchState := branch;
    if wasActive then
      frame.PriorAggregate := branch
    else
      // nothing below a dead frame can ever be live, including its else
      frame.PriorAggregate := tsTrue;
    FFrames.Add(frame);
    Exit;
  end;

  if SameText(name, 'ELSEIF') then
  begin
    if FFrames.Count = 0 then
    begin
      Warn(fileName, line, '{$ELSEIF} without a matching {$IF}');
      Exit;
    end;
    frame := FFrames[FFrames.Count - 1];
    branch := TConditionalEvaluator.Evaluate(parameter, FDefines);
    if (branch = tsUnknown) and (frame.PriorAggregate <> tsTrue) then
    begin
      frame.PendingWarning := Format('cannot evaluate {$ELSEIF %s}, taking every branch', [parameter]);
      frame.WarningFile := fileName;
      frame.WarningLine := line;
      frame.Reported := false;
    end;
    frame.BranchState := TriStateAnd(TriStateNot(frame.PriorAggregate), branch);
    frame.PriorAggregate := TriStateOr(frame.PriorAggregate, branch);
    frame.DisplayText := parameter;
    frame.ChainText := frame.ChainText + ' or ' + parameter;
    FFrames[FFrames.Count - 1] := frame;
    Exit;
  end;

  if SameText(name, 'ELSE') then
  begin
    if FFrames.Count = 0 then
    begin
      Warn(fileName, line, '{$ELSE} without a matching {$IF}');
      Exit;
    end;
    frame := FFrames[FFrames.Count - 1];
    frame.BranchState := TriStateNot(frame.PriorAggregate);
    frame.DisplayText := 'not (' + frame.ChainText + ')';
    FFrames[FFrames.Count - 1] := frame;
    Exit;
  end;

  if SameText(name, 'ENDIF') or SameText(name, 'IFEND') then
  begin
    if FFrames.Count = 0 then
      Warn(fileName, line, Format('{$%s} without a matching {$IF}', [UpperCase(name)]))
    else
      FFrames.Delete(FFrames.Count - 1);
    Exit;
  end;

  if not wasActive then
    Exit;

  if SameText(name, 'DEFINE') then
  begin
    FDefines.Define(parameter);
    Exit;
  end;

  if SameText(name, 'UNDEF') then
  begin
    FDefines.Undefine(parameter);
    Exit;
  end;

  if SameText(name, 'I') or SameText(name, 'INCLUDE') then
    HandleInclude(parameter, fileName, line);
end;

procedure TUnitScanner.ScanBuffer(const source : string; const fileName : string);
var
  scan : integer;
  len : integer;
  line : integer;
  start : integer;
  startLine : integer;
  identifier : string;
  literal : string;

  procedure ConsumeNewLine;
  begin
    // handle CRLF, LF and lone CR the same way
    if (source[scan] = #13) and (scan < len) and (source[scan + 1] = #10) then
      Inc(scan, 2)
    else
      Inc(scan);
    Inc(line);
  end;

begin
  scan := 1;
  len := Length(source);
  line := 1;

  while scan <= len do
  begin
    // --- end of line ---
    if CharInSet(source[scan], [#13, #10]) then
    begin
      ConsumeNewLine;
      Continue;
    end;

    if source[scan].IsWhiteSpace then
    begin
      Inc(scan);
      Continue;
    end;

    // --- line comment ---
    if (source[scan] = '/') and (scan < len) and (source[scan + 1] = '/') then
    begin
      while (scan <= len) and not CharInSet(source[scan], [#13, #10]) do
        Inc(scan);
      Continue;
    end;

    // --- brace comment or directive ---
    if source[scan] = '{' then
    begin
      startLine := line;
      Inc(scan);
      if (scan <= len) and (source[scan] = '$') then
      begin
        Inc(scan);
        start := scan;
        while (scan <= len) and (source[scan] <> '}') do
        begin
          if CharInSet(source[scan], [#13, #10]) then
            ConsumeNewLine
          else
            Inc(scan);
        end;
        HandleDirective(Copy(source, start, scan - start), fileName, startLine);
      end
      else
      begin
        while (scan <= len) and (source[scan] <> '}') do
        begin
          if CharInSet(source[scan], [#13, #10]) then
            ConsumeNewLine
          else
            Inc(scan);
        end;
      end;
      if scan <= len then
        Inc(scan); // the closing brace
      Continue;
    end;

    // --- (* *) comment or directive ---
    if (source[scan] = '(') and (scan < len) and (source[scan + 1] = '*') then
    begin
      startLine := line;
      Inc(scan, 2);
      if (scan <= len) and (source[scan] = '$') then
        Inc(scan);
      start := scan;
      while scan <= len do
      begin
        if (source[scan] = '*') and (scan < len) and (source[scan + 1] = ')') then
          Break;
        if CharInSet(source[scan], [#13, #10]) then
          ConsumeNewLine
        else
          Inc(scan);
      end;
      if (start > 1) and (source[start - 1] = '$') then
        HandleDirective(Copy(source, start, scan - start), fileName, startLine);
      if scan < len then
        Inc(scan, 2)  // the closing *)
      else
        scan := len + 1;
      Continue;
    end;

    // --- string literal ---
    if source[scan] = '''' then
    begin
      Inc(scan);
      start := scan;
      literal := '';
      while scan <= len do
      begin
        if source[scan] = '''' then
        begin
          // a doubled quote is an escaped quote, not the end of the literal
          if (scan < len) and (source[scan + 1] = '''') then
          begin
            literal := literal + Copy(source, start, scan - start) + '''';
            Inc(scan, 2);
            start := scan;
            Continue;
          end;
          Break;
        end;
        if CharInSet(source[scan], [#13, #10]) then
          Break; // unterminated - do not run off into the rest of the file
        Inc(scan);
      end;
      literal := literal + Copy(source, start, scan - start);
      if scan <= len then
        Inc(scan);
      if FInUses and FExpectingInPath and IsActive then
      begin
        FPendingInPath := literal;
        FExpectingInPath := false;
      end;
      Continue;
    end;

    // --- identifier, possibly dotted and possibly & escaped ---
    if source[scan].IsLetter or (source[scan] = '_') or (source[scan] = '&') then
    begin
      if source[scan] = '&' then
        Inc(scan);
      start := scan;
      while scan <= len do
      begin
        if source[scan].IsLetterOrDigit or (source[scan] = '_') then
          Inc(scan)
        else if (source[scan] = '.') and (scan < len) and
                (source[scan + 1].IsLetter or (source[scan + 1] = '_')) then
          // a dotted unit name is one name, not two
          Inc(scan)
        else
          Break;
      end;
      identifier := Copy(source, start, scan - start);
      HandleIdentifier(identifier, fileName, line);
      Continue;
    end;

    // --- number, including hex and character literals ---
    if source[scan].IsDigit or (source[scan] = '$') or (source[scan] = '#') then
    begin
      Inc(scan);
      while (scan <= len) and (source[scan].IsLetterOrDigit or (source[scan] = '.')) do
        Inc(scan);
      Continue;
    end;

    // --- punctuation that matters inside a uses clause ---
    if IsActive and FInUses then
    begin
      if source[scan] = ',' then
        FlushPendingEntry
      else if source[scan] = ';' then
      begin
        FlushPendingEntry;
        FInUses := false;
      end;
    end;
    Inc(scan);
  end;
end;

end.
