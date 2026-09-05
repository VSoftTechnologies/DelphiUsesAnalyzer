unit DUA.Tests.Scanner;

interface

uses
  Spring.Collections,
  DUnitX.TestFramework,
  DUA.Types,
  DUA.Defines,
  DUA.Scanner;

type
  /// <summary>
  ///   An include resolver backed by a dictionary rather than the file system, so the
  ///   scanner tests never touch disk.
  /// </summary>
  TFakeIncludeResolver = class(TInterfacedObject, IIncludeResolver)
  private
    FFiles : IDictionary<string, string>;
  protected
    function TryResolve(const parentFileName : string; const includeName : string;
                        out resolvedFileName : string; out content : string) : boolean;
  public
    constructor Create;
    procedure AddFile(const name : string; const content : string);
  end;

  [TestFixture]
  TScannerTests = class
  private
    FDefines : IDefineSet;
    FIncludes : TFakeIncludeResolver;
    FResolver : IIncludeResolver;
    function Scan(const source : string) : IScanResult;
    function ScanNamed(const source : string; const fileName : string) : IScanResult;
    function EntryNames(const scanResult : IScanResult) : string;
    function FindEntry(const scanResult : IScanResult; const unitName : string) : TUsesEntry;
  public
    [Setup]
    procedure Setup;

    // --- unit header ---
    [Test] procedure ReadsUnitName;
    [Test] procedure ReadsDottedUnitName;
    [Test] procedure ReadsProgramNameAndFlagsItAsAProgram;
    [Test] procedure ReadsLibraryName;
    [Test] procedure AUnitIsNotAProgram;

    // --- uses clauses ---
    [Test] procedure CollectsInterfaceUses;
    [Test] procedure CollectsImplementationUses;
    [Test] procedure SeparatesInterfaceFromImplementation;
    [Test] procedure CollectsProgramUses;
    [Test] procedure CollectsDottedUnitNames;
    [Test] procedure CollectsInPathFromAProgram;
    [Test] procedure CollectsInPathWithSubfolder;
    [Test] procedure UnitsWithoutAnInPathHaveAnEmptyInPath;
    [Test] procedure HandlesAUsesClauseSpanningManyLines;
    [Test] procedure IgnoresTheWordUsesInsideAnIdentifier;

    // --- comments and strings ---
    [Test] procedure IgnoresLineComments;
    [Test] procedure IgnoresBraceComments;
    [Test] procedure IgnoresParenStarComments;
    [Test] procedure IgnoresACommentedOutUnitInsideAClause;
    [Test] procedure IgnoresTheWordUsesInsideAStringLiteral;
    [Test] procedure HandlesDoubledQuotesInStringLiterals;

    // --- positions ---
    [Test] procedure RecordsTheLineNumberOfEachEntry;
    [Test] procedure RecordsTheFileNameOfEachEntry;

    // --- conditionals ---
    [Test] procedure IfdefTrueCollectsTheUnitAsConditional;
    [Test] procedure IfdefFalseSkipsTheUnit;
    [Test] procedure IfndefInvertsTheTest;
    [Test] procedure ElseBranchIsTakenWhenTheIfdefIsFalse;
    [Test] procedure ElseBranchIsSkippedWhenTheIfdefIsTrue;
    [Test] procedure NestedConditionalsBothHaveToPass;
    [Test] procedure IfDirectiveIsEvaluated;
    [Test] procedure ElseIfChainStopsAtTheFirstTrueBranch;
    [Test] procedure ElseAfterElseIfIsOnlyTakenWhenEveryBranchFailed;
    [Test] procedure UnconditionalEntriesHaveNoCondition;
    [Test] procedure ConditionTextRecordsTheEnclosingDirectives;

    // --- unknown conditionals take every branch ---
    [Test] procedure UnknownIfTakesBothBranches;
    [Test] procedure UnknownIfMarksEntriesAsUnevaluated;
    [Test] procedure UnknownIfProducesAWarning;
    [Test] procedure IfOptIsTreatedAsUnknown;
    [Test] procedure IfOptNeverWarns;
    [Test] procedure AnUnknownIfAwayFromAUsesClauseDoesNotWarn;
    [Test] procedure AnUnknownIfIsWarnedAboutOnlyOnce;
    [Test] procedure AWarningPointsAtTheDirectiveNotTheUnit;
    [Test] procedure ConditionalNestedInsideAnUnknownIsStillUnevaluated;

    // --- define and undef ---
    [Test] procedure DefineDirectiveAffectsLaterIfdefs;
    [Test] procedure UndefDirectiveAffectsLaterIfdefs;
    [Test] procedure DefineInsideAnInactiveBranchIsNotApplied;
    [Test] procedure ScanningDoesNotMutateTheCallersDefines;

    // --- includes ---
    [Test] procedure IncludeFileDefinesAreVisibleToTheIncludingUnit;
    [Test] procedure IncludeFileCanContributeUsesEntries;
    [Test] procedure EntriesFromAnIncludeRecordTheIncludeFileName;
    [Test] procedure IncludeDirectiveAcceptsTheLongForm;
    [Test] procedure MissingIncludeProducesAWarning;
    [Test] procedure IncludeSwitchIsNotAnIncludeFile;
    [Test] procedure IncludeOfACompilerValueIsNotAnIncludeFile;
    [Test] procedure IncludeInsideAnInactiveBranchIsNotRead;
    [Test] procedure RecursiveIncludeDoesNotHang;
    [Test] procedure IncludedFilesAreReported;
  end;

implementation

uses
  System.SysUtils;

const
  CRLF = #13#10;

{ TFakeIncludeResolver }

constructor TFakeIncludeResolver.Create;
begin
  inherited Create;
  FFiles := TCollections.CreateDictionary<string, string>;
end;

procedure TFakeIncludeResolver.AddFile(const name : string; const content : string);
begin
  FFiles[LowerCase(name)] := content;
end;

function TFakeIncludeResolver.TryResolve(const parentFileName : string; const includeName : string;
  out resolvedFileName : string; out content : string) : boolean;
begin
  resolvedFileName := '';
  content := '';
  result := FFiles.TryGetValue(LowerCase(includeName), content);
  if result then
    resolvedFileName := includeName;
end;

{ TScannerTests }

procedure TScannerTests.Setup;
begin
  FDefines := TDefineSet.Create;
  FDefines.Define('MSWINDOWS');
  FDefines.Define('WIN32');
  FDefines.SetNumeric('CompilerVersion', 37.0);
  FIncludes := TFakeIncludeResolver.Create;
  FResolver := FIncludes;
end;

function TScannerTests.Scan(const source : string) : IScanResult;
begin
  result := ScanNamed(source, 'Test.pas');
end;

function TScannerTests.ScanNamed(const source : string; const fileName : string) : IScanResult;
var
  scanner : IUnitScanner;
begin
  scanner := TUnitScanner.Create(FResolver);
  result := scanner.Scan(source, fileName, FDefines);
end;

function TScannerTests.EntryNames(const scanResult : IScanResult) : string;
var
  entry : TUsesEntry;
begin
  result := '';
  for entry in scanResult.Entries do
  begin
    if result <> '' then
      result := result + ',';
    result := result + entry.UnitName;
  end;
end;

function TScannerTests.FindEntry(const scanResult : IScanResult; const unitName : string) : TUsesEntry;
var
  entry : TUsesEntry;
begin
  for entry in scanResult.Entries do
    if SameText(entry.UnitName, unitName) then
      Exit(entry);
  Assert.Fail('no entry found for ' + unitName + '. got: ' + EntryNames(scanResult));
end;

procedure TScannerTests.ReadsUnitName;
begin
  Assert.AreEqual('MyUnit', Scan('unit MyUnit;' + CRLF + 'interface' + CRLF + 'implementation' + CRLF + 'end.').UnitName);
end;

procedure TScannerTests.ReadsDottedUnitName;
begin
  Assert.AreEqual('My.Nested.Unit', Scan('unit My.Nested.Unit;' + CRLF + 'interface' + CRLF + 'end.').UnitName);
end;

procedure TScannerTests.ReadsProgramNameAndFlagsItAsAProgram;
var
  scanResult : IScanResult;
begin
  scanResult := Scan('program MyApp;' + CRLF + 'begin' + CRLF + 'end.');
  Assert.AreEqual('MyApp', scanResult.UnitName);
  Assert.IsTrue(scanResult.IsProgram);
end;

procedure TScannerTests.ReadsLibraryName;
var
  scanResult : IScanResult;
begin
  scanResult := Scan('library MyLib;' + CRLF + 'begin' + CRLF + 'end.');
  Assert.AreEqual('MyLib', scanResult.UnitName);
  Assert.IsTrue(scanResult.IsProgram);
end;

procedure TScannerTests.AUnitIsNotAProgram;
begin
  Assert.IsFalse(Scan('unit MyUnit;' + CRLF + 'interface' + CRLF + 'end.').IsProgram);
end;

procedure TScannerTests.CollectsInterfaceUses;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses System.SysUtils, System.Classes;' + CRLF +
    'implementation' + CRLF +
    'end.');

  Assert.AreEqual('System.SysUtils,System.Classes', EntryNames(scanResult));
  Assert.AreEqual(UsesSectionToString(usInterface),
    UsesSectionToString(FindEntry(scanResult, 'System.SysUtils').Section));
end;

procedure TScannerTests.CollectsImplementationUses;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'implementation' + CRLF +
    'uses Vcl.Forms;' + CRLF +
    'end.');

  Assert.AreEqual(UsesSectionToString(usImplementation),
    UsesSectionToString(FindEntry(scanResult, 'Vcl.Forms').Section));
end;

procedure TScannerTests.SeparatesInterfaceFromImplementation;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses System.Classes;' + CRLF +
    'implementation' + CRLF +
    'uses Vcl.Forms;' + CRLF +
    'end.');

  Assert.AreEqual(UsesSectionToString(usInterface),
    UsesSectionToString(FindEntry(scanResult, 'System.Classes').Section));
  Assert.AreEqual(UsesSectionToString(usImplementation),
    UsesSectionToString(FindEntry(scanResult, 'Vcl.Forms').Section));
end;

procedure TScannerTests.CollectsProgramUses;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'program MyApp;' + CRLF +
    'uses System.SysUtils;' + CRLF +
    'begin' + CRLF +
    'end.');

  Assert.AreEqual(UsesSectionToString(usProgram),
    UsesSectionToString(FindEntry(scanResult, 'System.SysUtils').Section));
end;

procedure TScannerTests.CollectsDottedUnitNames;
begin
  Assert.AreEqual('Vcl.Imaging.Jpeg', EntryNames(Scan(
    'unit MyUnit;' + CRLF + 'interface' + CRLF + 'uses Vcl.Imaging.Jpeg;' + CRLF + 'end.')));
end;

procedure TScannerTests.CollectsInPathFromAProgram;
var
  entry : TUsesEntry;
begin
  entry := FindEntry(Scan(
    'program MyApp;' + CRLF +
    'uses' + CRLF +
    '  MyUnit in ''MyUnit.pas'';' + CRLF +
    'begin' + CRLF +
    'end.'), 'MyUnit');

  Assert.AreEqual('MyUnit.pas', entry.InPath);
end;

procedure TScannerTests.CollectsInPathWithSubfolder;
var
  entry : TUsesEntry;
begin
  entry := FindEntry(Scan(
    'program MyApp;' + CRLF +
    'uses' + CRLF +
    '  MyUnit in ''..\Shared\MyUnit.pas'';' + CRLF +
    'begin' + CRLF +
    'end.'), 'MyUnit');

  Assert.AreEqual('..\Shared\MyUnit.pas', entry.InPath);
end;

procedure TScannerTests.UnitsWithoutAnInPathHaveAnEmptyInPath;
begin
  Assert.AreEqual('', FindEntry(Scan(
    'unit MyUnit;' + CRLF + 'interface' + CRLF + 'uses System.Classes;' + CRLF + 'end.'),
    'System.Classes').InPath);
end;

procedure TScannerTests.HandlesAUsesClauseSpanningManyLines;
begin
  Assert.AreEqual('System.SysUtils,System.Classes,Vcl.Forms', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  System.SysUtils,' + CRLF +
    '  System.Classes,' + CRLF +
    '  Vcl.Forms;' + CRLF +
    'implementation' + CRLF +
    'end.')));
end;

procedure TScannerTests.IgnoresTheWordUsesInsideAnIdentifier;
begin
  // "Houses" contains "uses" - a naive substring search would trip over it
  Assert.AreEqual('System.Classes', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses System.Classes;' + CRLF +
    'var Houses : integer;' + CRLF +
    'implementation' + CRLF +
    'end.')));
end;

procedure TScannerTests.IgnoresLineComments;
begin
  Assert.AreEqual('System.Classes', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    '// uses Vcl.Forms;' + CRLF +
    'uses System.Classes;' + CRLF +
    'end.')));
end;

procedure TScannerTests.IgnoresBraceComments;
begin
  Assert.AreEqual('System.Classes', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    '{ uses Vcl.Forms; }' + CRLF +
    'uses System.Classes;' + CRLF +
    'end.')));
end;

procedure TScannerTests.IgnoresParenStarComments;
begin
  Assert.AreEqual('System.Classes', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    '(* uses Vcl.Forms;' + CRLF +
    '   still a comment *)' + CRLF +
    'uses System.Classes;' + CRLF +
    'end.')));
end;

procedure TScannerTests.IgnoresACommentedOutUnitInsideAClause;
begin
  Assert.AreEqual('System.Classes,System.SysUtils', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  System.Classes,' + CRLF +
    '  { Vcl.Forms, }' + CRLF +
    '  System.SysUtils;' + CRLF +
    'end.')));
end;

procedure TScannerTests.IgnoresTheWordUsesInsideAStringLiteral;
begin
  Assert.AreEqual('System.Classes', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses System.Classes;' + CRLF +
    'const C = ''uses Vcl.Forms;'';' + CRLF +
    'implementation' + CRLF +
    'end.')));
end;

procedure TScannerTests.HandlesDoubledQuotesInStringLiterals;
begin
  // the '' in the middle is an escaped quote, not the end of the string
  Assert.AreEqual('System.Classes', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'const C = ''it''''s not the end'';' + CRLF +
    'uses System.Classes;' + CRLF +
    'implementation' + CRLF +
    'end.')));
end;

procedure TScannerTests.RecordsTheLineNumberOfEachEntry;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +   // 1
    'interface' + CRLF +      // 2
    'uses' + CRLF +           // 3
    '  System.Classes,' + CRLF + // 4
    '  Vcl.Forms;' + CRLF +   // 5
    'end.');

  Assert.AreEqual(4, FindEntry(scanResult, 'System.Classes').Line);
  Assert.AreEqual(5, FindEntry(scanResult, 'Vcl.Forms').Line);
end;

procedure TScannerTests.RecordsTheFileNameOfEachEntry;
begin
  Assert.AreEqual('C:\src\MyUnit.pas', FindEntry(ScanNamed(
    'unit MyUnit;' + CRLF + 'interface' + CRLF + 'uses System.Classes;' + CRLF + 'end.',
    'C:\src\MyUnit.pas'), 'System.Classes').FileName);
end;

procedure TScannerTests.IfdefTrueCollectsTheUnitAsConditional;
var
  entry : TUsesEntry;
begin
  entry := FindEntry(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF MSWINDOWS}' + CRLF +
    '  Vcl.Forms,' + CRLF +
    '  {$ENDIF}' + CRLF +
    '  System.Classes;' + CRLF +
    'end.'), 'Vcl.Forms');

  Assert.AreEqual(EdgeCertaintyToString(ecConditional), EdgeCertaintyToString(entry.Certainty));
end;

procedure TScannerTests.IfdefFalseSkipsTheUnit;
begin
  Assert.AreEqual('System.Classes', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF LINUX}' + CRLF +
    '  Posix.Unistd,' + CRLF +
    '  {$ENDIF}' + CRLF +
    '  System.Classes;' + CRLF +
    'end.')));
end;

procedure TScannerTests.IfndefInvertsTheTest;
begin
  Assert.AreEqual('System.Classes', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFNDEF MSWINDOWS}' + CRLF +
    '  Posix.Unistd,' + CRLF +
    '  {$ENDIF}' + CRLF +
    '  System.Classes;' + CRLF +
    'end.')));
end;

procedure TScannerTests.ElseBranchIsTakenWhenTheIfdefIsFalse;
begin
  Assert.AreEqual('Vcl.Forms', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF LINUX}' + CRLF +
    '  Posix.Unistd' + CRLF +
    '  {$ELSE}' + CRLF +
    '  Vcl.Forms' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.')));
end;

procedure TScannerTests.ElseBranchIsSkippedWhenTheIfdefIsTrue;
begin
  Assert.AreEqual('Vcl.Forms', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF MSWINDOWS}' + CRLF +
    '  Vcl.Forms' + CRLF +
    '  {$ELSE}' + CRLF +
    '  Posix.Unistd' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.')));
end;

procedure TScannerTests.NestedConditionalsBothHaveToPass;
begin
  Assert.AreEqual('Keep', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF MSWINDOWS}' + CRLF +
    '    {$IFDEF WIN32}' + CRLF +
    '    Keep,' + CRLF +
    '    {$ENDIF}' + CRLF +
    '    {$IFDEF WIN64}' + CRLF +
    '    Drop,' + CRLF +
    '    {$ENDIF}' + CRLF +
    '  {$ENDIF}' + CRLF +
    '  ;' + CRLF +
    'end.')));
end;

procedure TScannerTests.IfDirectiveIsEvaluated;
begin
  Assert.AreEqual('Modern', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IF CompilerVersion >= 36}' + CRLF +
    '  Modern' + CRLF +
    '  {$ELSE}' + CRLF +
    '  Legacy' + CRLF +
    '  {$IFEND};' + CRLF +
    'end.')));
end;

procedure TScannerTests.ElseIfChainStopsAtTheFirstTrueBranch;
begin
  Assert.AreEqual('Windows', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IF Defined(LINUX)}' + CRLF +
    '  Linux' + CRLF +
    '  {$ELSEIF Defined(MSWINDOWS)}' + CRLF +
    '  Windows' + CRLF +
    '  {$ELSEIF Defined(WIN32)}' + CRLF +
    '  AlsoTrueButLater' + CRLF +
    '  {$ELSE}' + CRLF +
    '  Fallback' + CRLF +
    '  {$IFEND};' + CRLF +
    'end.')));
end;

procedure TScannerTests.ElseAfterElseIfIsOnlyTakenWhenEveryBranchFailed;
begin
  Assert.AreEqual('Fallback', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IF Defined(LINUX)}' + CRLF +
    '  Linux' + CRLF +
    '  {$ELSEIF Defined(ANDROID)}' + CRLF +
    '  Android' + CRLF +
    '  {$ELSE}' + CRLF +
    '  Fallback' + CRLF +
    '  {$IFEND};' + CRLF +
    'end.')));
end;

procedure TScannerTests.UnconditionalEntriesHaveNoCondition;
var
  entry : TUsesEntry;
begin
  entry := FindEntry(Scan(
    'unit MyUnit;' + CRLF + 'interface' + CRLF + 'uses System.Classes;' + CRLF + 'end.'),
    'System.Classes');

  Assert.AreEqual(EdgeCertaintyToString(ecUnconditional), EdgeCertaintyToString(entry.Certainty));
  Assert.AreEqual('', entry.Condition);
end;

procedure TScannerTests.ConditionTextRecordsTheEnclosingDirectives;
var
  entry : TUsesEntry;
begin
  entry := FindEntry(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF MSWINDOWS}' + CRLF +
    '  Vcl.Forms' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.'), 'Vcl.Forms');

  Assert.Contains(entry.Condition, 'MSWINDOWS');
end;

procedure TScannerTests.UnknownIfTakesBothBranches;
begin
  // Declared() is not something we can evaluate, so both units must survive - losing
  // either one could hide the dependency the user is hunting for.
  Assert.AreEqual('Maybe,OrMaybeNot', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IF Declared(SomeSymbol)}' + CRLF +
    '  Maybe' + CRLF +
    '  {$ELSE}' + CRLF +
    '  OrMaybeNot' + CRLF +
    '  {$IFEND};' + CRLF +
    'end.')));
end;

procedure TScannerTests.UnknownIfMarksEntriesAsUnevaluated;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IF Declared(SomeSymbol)}' + CRLF +
    '  Maybe' + CRLF +
    '  {$IFEND};' + CRLF +
    'end.');

  Assert.AreEqual(EdgeCertaintyToString(ecUnevaluated),
    EdgeCertaintyToString(FindEntry(scanResult, 'Maybe').Certainty));
end;

procedure TScannerTests.UnknownIfProducesAWarning;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    '{$IF Declared(SomeSymbol)}' + CRLF +
    'uses Maybe;' + CRLF +
    '{$IFEND}' + CRLF +
    'end.');

  Assert.AreEqual<integer>(1, scanResult.Warnings.Count, 'expected exactly one warning');
  Assert.Contains(scanResult.Warnings[0].Message, 'Declared(SomeSymbol)');
  Assert.AreEqual(3, scanResult.Warnings[0].Line);
end;

procedure TScannerTests.IfOptIsTreatedAsUnknown;
begin
  // we have no idea what the compiler switch state is, so both branches survive
  Assert.AreEqual('WithRangeChecks,WithoutRangeChecks', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFOPT R+}' + CRLF +
    '  WithRangeChecks' + CRLF +
    '  {$ELSE}' + CRLF +
    '  WithoutRangeChecks' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.')));
end;

procedure TScannerTests.IfOptNeverWarns;
var
  scanResult : IScanResult;
begin
  // {$IFOPT} asks about compiler switches, which have nothing to do with what a unit
  // uses. Both branches are still taken so no dependency is lost, but there is nothing
  // here worth telling anyone about.
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFOPT R+}' + CRLF +
    '  WithRangeChecks' + CRLF +
    '  {$ELSE}' + CRLF +
    '  WithoutRangeChecks' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.');

  Assert.AreEqual('WithRangeChecks,WithoutRangeChecks', EntryNames(scanResult));
  Assert.AreEqual<integer>(0, scanResult.Warnings.Count);
end;

procedure TScannerTests.AnUnknownIfAwayFromAUsesClauseDoesNotWarn;
var
  scanResult : IScanResult;
begin
  // real code is full of conditionals that guard declarations rather than uses clauses,
  // and warning about every one of them buries the ones that matter
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    '{$IF Declared(SomeSymbol)}' + CRLF +
    '{$DEFINE HAVE_IT}' + CRLF +
    '{$IFEND}' + CRLF +
    'interface' + CRLF +
    'uses System.Classes;' + CRLF +
    'implementation' + CRLF +
    '{$IF Declared(Another)}' + CRLF +
    'const C = 1;' + CRLF +
    '{$IFEND}' + CRLF +
    'end.');

  Assert.AreEqual('System.Classes', EntryNames(scanResult));
  Assert.AreEqual<integer>(0, scanResult.Warnings.Count);
end;

procedure TScannerTests.AnUnknownIfIsWarnedAboutOnlyOnce;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IF Declared(SomeSymbol)}' + CRLF +
    '  First,' + CRLF +
    '  Second,' + CRLF +
    '  Third' + CRLF +
    '  {$IFEND};' + CRLF +
    'end.');

  Assert.AreEqual('First,Second,Third', EntryNames(scanResult));
  Assert.AreEqual<integer>(1, scanResult.Warnings.Count,
    'one unevaluatable directive is one warning, however many units it guards');
end;

procedure TScannerTests.AWarningPointsAtTheDirectiveNotTheUnit;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IF Declared(SomeSymbol)}' + CRLF +
    '  Maybe' + CRLF +
    '  {$IFEND};' + CRLF +
    'end.');

  Assert.AreEqual<integer>(1, scanResult.Warnings.Count);
  Assert.AreEqual(4, scanResult.Warnings[0].Line, 'the directive is the thing to go and look at');
end;

procedure TScannerTests.ConditionalNestedInsideAnUnknownIsStillUnevaluated;
var
  entry : TUsesEntry;
begin
  entry := FindEntry(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IF Declared(SomeSymbol)}' + CRLF +
    '    {$IFDEF MSWINDOWS}' + CRLF +
    '    Vcl.Forms' + CRLF +
    '    {$ENDIF}' + CRLF +
    '  {$IFEND};' + CRLF +
    'end.'), 'Vcl.Forms');

  Assert.AreEqual(EdgeCertaintyToString(ecUnevaluated), EdgeCertaintyToString(entry.Certainty));
end;

procedure TScannerTests.DefineDirectiveAffectsLaterIfdefs;
begin
  Assert.AreEqual('Included', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    '{$DEFINE MY_FEATURE}' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF MY_FEATURE}' + CRLF +
    '  Included' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.')));
end;

procedure TScannerTests.UndefDirectiveAffectsLaterIfdefs;
begin
  Assert.AreEqual('', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    '{$UNDEF MSWINDOWS}' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF MSWINDOWS}' + CRLF +
    '  Vcl.Forms' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.')));
end;

procedure TScannerTests.DefineInsideAnInactiveBranchIsNotApplied;
begin
  Assert.AreEqual('', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    '{$IFDEF LINUX}' + CRLF +
    '{$DEFINE MY_FEATURE}' + CRLF +
    '{$ENDIF}' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF MY_FEATURE}' + CRLF +
    '  ShouldNotBeHere' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.')));
end;

procedure TScannerTests.ScanningDoesNotMutateTheCallersDefines;
begin
  Scan('unit MyUnit;' + CRLF + '{$DEFINE LEAKED}' + CRLF + '{$UNDEF MSWINDOWS}' + CRLF +
       'interface' + CRLF + 'end.');

  Assert.IsFalse(FDefines.IsDefined('LEAKED'), 'a unit define leaked out of the scan');
  Assert.IsTrue(FDefines.IsDefined('MSWINDOWS'), 'a unit undef leaked out of the scan');
end;

procedure TScannerTests.IncludeFileDefinesAreVisibleToTheIncludingUnit;
begin
  FIncludes.AddFile('features.inc', '{$DEFINE MY_FEATURE}');

  Assert.AreEqual('Included', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    '{$I features.inc}' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF MY_FEATURE}' + CRLF +
    '  Included' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.')));
end;

procedure TScannerTests.IncludeFileCanContributeUsesEntries;
begin
  FIncludes.AddFile('extra.inc', 'System.Classes,');

  Assert.AreEqual('System.Classes,Vcl.Forms', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$I extra.inc}' + CRLF +
    '  Vcl.Forms;' + CRLF +
    'end.')));
end;

procedure TScannerTests.EntriesFromAnIncludeRecordTheIncludeFileName;
var
  entry : TUsesEntry;
begin
  FIncludes.AddFile('extra.inc', 'System.Classes,');

  entry := FindEntry(Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$I extra.inc}' + CRLF +
    '  Vcl.Forms;' + CRLF +
    'end.'), 'System.Classes');

  Assert.AreEqual('extra.inc', entry.FileName);
  Assert.AreEqual(1, entry.Line, 'line numbers restart inside the include');
end;

procedure TScannerTests.IncludeDirectiveAcceptsTheLongForm;
begin
  FIncludes.AddFile('features.inc', '{$DEFINE MY_FEATURE}');

  Assert.AreEqual('Included', EntryNames(Scan(
    'unit MyUnit;' + CRLF +
    '{$INCLUDE features.inc}' + CRLF +
    'interface' + CRLF +
    'uses' + CRLF +
    '  {$IFDEF MY_FEATURE}' + CRLF +
    '  Included' + CRLF +
    '  {$ENDIF};' + CRLF +
    'end.')));
end;

procedure TScannerTests.MissingIncludeProducesAWarning;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    '{$I nosuchfile.inc}' + CRLF +
    'interface' + CRLF +
    'end.');

  Assert.AreEqual<integer>(1, scanResult.Warnings.Count);
  Assert.Contains(scanResult.Warnings[0].Message, 'nosuchfile.inc');
end;

procedure TScannerTests.IncludeSwitchIsNotAnIncludeFile;
var
  scanResult : IScanResult;
begin
  // {$I+} and {$I-} are the io checking switch, not an include
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    '{$I+}' + CRLF +
    '{$I-}' + CRLF +
    'interface' + CRLF +
    'end.');

  Assert.AreEqual<integer>(0, scanResult.Warnings.Count, 'io check switch treated as an include');
end;

procedure TScannerTests.IncludeOfACompilerValueIsNotAnIncludeFile;
var
  scanResult : IScanResult;
begin
  // {$I %DATE%} inlines a compiler value as a string, it does not read a file
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    'interface' + CRLF +
    'const BuildDate = {$I %DATE%};' + CRLF +
    'end.');

  Assert.AreEqual<integer>(0, scanResult.Warnings.Count, 'compiler value treated as an include');
end;

procedure TScannerTests.IncludeInsideAnInactiveBranchIsNotRead;
var
  scanResult : IScanResult;
begin
  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    '{$IFDEF LINUX}' + CRLF +
    '{$I nosuchfile.inc}' + CRLF +
    '{$ENDIF}' + CRLF +
    'interface' + CRLF +
    'end.');

  Assert.AreEqual<integer>(0, scanResult.Warnings.Count, 'read an include in a dead branch');
end;

procedure TScannerTests.RecursiveIncludeDoesNotHang;
var
  scanResult : IScanResult;
begin
  FIncludes.AddFile('a.inc', '{$I b.inc}');
  FIncludes.AddFile('b.inc', '{$I a.inc}');

  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    '{$I a.inc}' + CRLF +
    'interface' + CRLF +
    'uses System.Classes;' + CRLF +
    'end.');

  Assert.AreEqual('System.Classes', EntryNames(scanResult), 'scan did not survive the cycle');
  Assert.IsTrue(scanResult.Warnings.Count > 0, 'an include cycle should be reported');
end;

procedure TScannerTests.IncludedFilesAreReported;
var
  scanResult : IScanResult;
begin
  FIncludes.AddFile('features.inc', '{$DEFINE MY_FEATURE}');

  scanResult := Scan(
    'unit MyUnit;' + CRLF +
    '{$I features.inc}' + CRLF +
    'interface' + CRLF +
    'end.');

  Assert.AreEqual<integer>(1, scanResult.IncludedFiles.Count);
  Assert.AreEqual('features.inc', scanResult.IncludedFiles[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TScannerTests);

end.
