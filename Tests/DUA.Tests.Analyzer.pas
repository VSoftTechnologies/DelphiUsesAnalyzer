unit DUA.Tests.Analyzer;

interface

uses
  DUnitX.TestFramework,
  DUA.Types,
  DUA.Analyzer;

type
  /// <summary>A copy of the fields a test cares about, so a nil edge is easy to spot.</summary>
  TGraphEdgeInfo = record
    Found : boolean;
    Section : TUsesSection;
    Certainty : TEdgeCertainty;
    Condition : string;
    Line : integer;
  end;

  /// <summary>
  ///   End to end, against the fixture project in TestData. Its only route to a vcl unit
  ///   runs through two intermediate units, the last hop guarded by {$IFDEF MSWINDOWS} -
  ///   which is the shape of the problem this tool exists to answer.
  /// </summary>
  [TestFixture]
  TAnalyzerTests = class
  private
    FAnalysis : IAnalysisResult;
    function Chain(const toUnit : string) : string;
    function EdgeTo(const toUnit : string) : TGraphEdgeInfo;
  public
    [Setup]
    procedure Setup;

    [Test] procedure FindsTheProgramAndItsTarget;
    [Test] procedure ResolvesEveryUnit;
    [Test] procedure RootIsTheProgram;

    [Test] procedure FindsTheChainFromTheProgramToTheVclUnit;
    [Test] procedure TheVclUnitIsRecordedAsRtl;
    [Test] procedure TheVclUnitIsNotParsed;
    [Test] procedure ProjectUnitsAreParsed;
    [Test] procedure EveryEdgeNamesAnExistingNodeExactly;

    [Test] procedure TheGuardedEdgeIsMarkedConditional;
    [Test] procedure TheGuardedEdgeNamesItsCondition;
    [Test] procedure AnOrdinaryEdgeIsUnconditional;
    [Test] procedure TheEdgeKnowsWhichSectionItCameFrom;

    [Test] procedure AnUnevaluatableConditionTakesBothBranches;
    [Test] procedure AnUnevaluatableConditionIsMarkedUnevaluated;
    [Test] procedure AnUnevaluatableConditionIsWarnedAbout;
  end;

  /// <summary>
  ///   One unit with two copies, each found from a different folder. The graph holds one
  ///   node per unit, so it has to keep the first copy found, read that copy and report
  ///   that copy - and say so when a later reference finds the other one.
  /// </summary>
  [TestFixture]
  TDuplicateUnitTests = class
  private
    FAnalysis : IAnalysisResult;
    function ConflictWarnings : TArray<TScanWarning>;
  public
    [Setup]
    procedure Setup;

    [Test] procedure TheFirstCopyFoundIsTheOneKept;
    [Test] procedure TheCopyKeptIsTheCopyRead;
    [Test] procedure TheOtherCopyIsNotRead;
    [Test] procedure TheOtherCopyIsWarnedAboutOnce;
    [Test] procedure TheWarningNamesBothCopies;
    [Test] procedure TheWarningIsWhereTheOtherCopyWasFound;
  end;

  /// <summary>
  ///   One file reached through two spellings of its folder - a search path with .. in it,
  ///   and the folder of a unit found next to it. Telling copies apart means comparing
  ///   files, so the same file must not come out as two.
  /// </summary>
  [TestFixture]
  TOneCopyTests = class
  private
    FAnalysis : IAnalysisResult;
  public
    [Setup]
    procedure Setup;

    [Test] procedure OneFileReachedTwoWaysIsNotTwoCopies;
    [Test] procedure AFileFoundThroughDotDotIsNamedWithoutIt;
  end;

  /// <summary>
  ///   The analysis appeared to hang on a large project, so it now reports as it goes.
  ///   These pin the reporting itself; the console only ever renders what it is given.
  /// </summary>
  [TestFixture]
  TAnalyzerProgressTests = class
  public
    [Test] procedure ReportsEveryPhaseInOrder;
    [Test] procedure ScannedCountRisesAndEndsAtTheUnitCount;
    [Test] procedure NamesTheUnitItJustRead;
    [Test] procedure AnalysisRunsWithoutAProgressCallback;

    [Test]
    [TestCase('reading',   'apReadingProject|0|0|Reading project', '|')]
    [TestCase('paths',     'apBuildingSearchPaths|0|0|Building search paths', '|')]
    [TestCase('scanning',  'apScanning|12|3|Scanning 12/15 units', '|')]
    [TestCase('finished',  'apFinished|99|0|Scanned 99 units', '|')]
    procedure ScanDescriptionReadsSensibly(const phase : string; const scanned : integer;
                                           const queued : integer; const expected : string);
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  System.TypInfo,
  Spring.Collections,
  DUA.Graph,
  DUA.Report.Console,
  DUA.Compiler.Environment,
  DUA.Compiler.Versions;

const
  VclUnit = 'Vcl.Graphics';

function FixtureProject : string;
var
  folder : string;
begin
  // the test exe runs from Tests\Debug\Win32, the fixture lives under Tests\TestData
  folder := ExtractFilePath(ParamStr(0));
  result := TPath.GetFullPath(TPath.Combine(folder, '..\..\TestData\SampleApp\SampleApp.dproj'));
end;

function DuplicateFixtureFolder : string;
begin
  result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\TestData\DuplicateApp'));
end;

function FirstCopy : string;
begin
  result := TPath.Combine(DuplicateFixtureFolder, 'First\DuplicateApp.Shared.pas');
end;

function SecondCopy : string;
begin
  result := TPath.Combine(DuplicateFixtureFolder, 'Second\DuplicateApp.Shared.pas');
end;

{ TAnalyzerTests }

procedure TAnalyzerTests.Setup;
var
  analyzer : IAnalyzer;
  options : TAnalyzerOptions;
  environment : IDelphiEnvironment;
begin
  environment := TDelphiEnvironment.Create;
  if environment.NewestInstalled = cvUnknown then
    Assert.Pass('no Delphi installed, so rtl units cannot be resolved');

  if not TFile.Exists(FixtureProject) then
    Assert.Fail('fixture project not found at ' + FixtureProject);

  options := Default(TAnalyzerOptions);
  options.ProjectFile := FixtureProject;
  options.Platform := 'Win32';
  options.Config := 'Debug';

  analyzer := TAnalyzer.Create;
  FAnalysis := analyzer.Analyze(options);
end;

function TAnalyzerTests.Chain(const toUnit : string) : string;
var
  chains : IReadOnlyList<TArray<string>>;
begin
  chains := FAnalysis.Graph.FindPaths(FAnalysis.RootUnit, toUnit, 1);
  if chains.Count = 0 then
    Exit('');
  result := string.Join('>', chains[0]);
end;

function TAnalyzerTests.EdgeTo(const toUnit : string) : TGraphEdgeInfo;
var
  edge : TGraphEdge;
begin
  result := Default(TGraphEdgeInfo);
  for edge in FAnalysis.Graph.Edges do
    if SameText(edge.ToUnit, toUnit) then
    begin
      result.Found := true;
      result.Section := edge.Section;
      result.Certainty := edge.Certainty;
      result.Condition := edge.Condition;
      result.Line := edge.Line;
      Exit;
    end;
end;

procedure TAnalyzerTests.FindsTheProgramAndItsTarget;
begin
  Assert.EndsWith('SampleApp.dpr', FAnalysis.DprFile);
  Assert.AreEqual('Win32', TDelphiPlatforms.ToName(FAnalysis.Platform));
  Assert.AreEqual('Debug', FAnalysis.Config);
end;

procedure TAnalyzerTests.ResolvesEveryUnit;
var
  node : TGraphNode;
  missing : string;
begin
  missing := '';
  for node in FAnalysis.Graph.Nodes do
    if node.Kind = ukUnresolved then
      missing := missing + ' ' + node.Name;

  Assert.AreEqual('', missing, 'these units did not resolve:' + missing);
end;

procedure TAnalyzerTests.RootIsTheProgram;
begin
  Assert.AreEqual('SampleApp', FAnalysis.RootUnit);
end;

procedure TAnalyzerTests.FindsTheChainFromTheProgramToTheVclUnit;
begin
  Assert.AreEqual('SampleApp>SampleApp.Middle>SampleApp.Inner>' + VclUnit, Chain(VclUnit));
end;

procedure TAnalyzerTests.TheVclUnitIsRecordedAsRtl;
var
  node : TGraphNode;
begin
  Assert.IsTrue(FAnalysis.Graph.TryFindNode(VclUnit, node), VclUnit + ' is not in the graph');
  Assert.AreEqual(UnitKindToString(ukRTL), UnitKindToString(node.Kind));
end;

procedure TAnalyzerTests.TheVclUnitIsNotParsed;
var
  node : TGraphNode;
begin
  FAnalysis.Graph.TryFindNode(VclUnit, node);
  Assert.IsFalse(node.Parsed, 'the walk should stop at the rtl boundary');
end;

procedure TAnalyzerTests.ProjectUnitsAreParsed;
var
  node : TGraphNode;
begin
  Assert.IsTrue(FAnalysis.Graph.TryFindNode('SampleApp.Inner', node));
  Assert.IsTrue(node.Parsed);
  Assert.AreEqual(UnitKindToString(ukProject), UnitKindToString(node.Kind));
end;

procedure TAnalyzerTests.EveryEdgeNamesAnExistingNodeExactly;
var
  edge : TGraphEdge;
  node : TGraphNode;
begin
  // source files spell the same unit several ways - WinAPi.Windows and Winapi.Windows -
  // so an edge has to carry the node's spelling, not whatever the file happened to use
  for edge in FAnalysis.Graph.Edges do
  begin
    Assert.IsTrue(FAnalysis.Graph.TryFindNode(edge.FromUnit, node), edge.FromUnit);
    Assert.AreEqual(node.Name, edge.FromUnit, 'edge from-name does not match the node');
    Assert.IsTrue(FAnalysis.Graph.TryFindNode(edge.ToUnit, node), edge.ToUnit);
    Assert.AreEqual(node.Name, edge.ToUnit, 'edge to-name does not match the node');
  end;
end;

procedure TAnalyzerTests.TheGuardedEdgeIsMarkedConditional;
var
  edge : TGraphEdgeInfo;
begin
  edge := EdgeTo(VclUnit);
  Assert.IsTrue(edge.Found);
  Assert.AreEqual(EdgeCertaintyToString(ecConditional), EdgeCertaintyToString(edge.Certainty));
end;

procedure TAnalyzerTests.TheGuardedEdgeNamesItsCondition;
begin
  Assert.Contains(EdgeTo(VclUnit).Condition, 'MSWINDOWS');
end;

procedure TAnalyzerTests.AnOrdinaryEdgeIsUnconditional;
begin
  Assert.AreEqual(EdgeCertaintyToString(ecUnconditional),
    EdgeCertaintyToString(EdgeTo('SampleApp.Middle').Certainty));
end;

procedure TAnalyzerTests.TheEdgeKnowsWhichSectionItCameFrom;
begin
  // SampleApp.Inner is used from the implementation section of SampleApp.Middle
  Assert.AreEqual(UsesSectionToString(usImplementation),
    UsesSectionToString(EdgeTo('SampleApp.Inner').Section));
end;

procedure TAnalyzerTests.AnUnevaluatableConditionTakesBothBranches;
begin
  // neither branch may be dropped, or the dependency being hunted could vanish
  Assert.IsTrue(FAnalysis.Graph.ContainsNode('System.DateUtils'), 'the if branch');
  Assert.IsTrue(FAnalysis.Graph.ContainsNode('System.Math'), 'the else branch');
end;

procedure TAnalyzerTests.AnUnevaluatableConditionIsMarkedUnevaluated;
begin
  Assert.AreEqual(EdgeCertaintyToString(ecUnevaluated),
    EdgeCertaintyToString(EdgeTo('System.DateUtils').Certainty));
  Assert.AreEqual(EdgeCertaintyToString(ecUnevaluated),
    EdgeCertaintyToString(EdgeTo('System.Math').Certainty));
end;

procedure TAnalyzerTests.AnUnevaluatableConditionIsWarnedAbout;
var
  warning : TScanWarning;
  found : boolean;
begin
  found := false;
  for warning in FAnalysis.Warnings do
    if warning.Message.Contains('SomeSymbolWeCannotSee') then
      found := true;

  Assert.IsTrue(found, 'an unevaluatable condition has to be reported, not silently guessed');
end;

{ TDuplicateUnitTests }

procedure TDuplicateUnitTests.Setup;
var
  analyzer : IAnalyzer;
  options : TAnalyzerOptions;
  environment : IDelphiEnvironment;
begin
  environment := TDelphiEnvironment.Create;
  if environment.NewestInstalled = cvUnknown then
    Assert.Pass('no Delphi installed, so the project cannot be prepared');

  options := Default(TAnalyzerOptions);
  options.ProjectFile := TPath.Combine(DuplicateFixtureFolder, 'DuplicateApp.dpr');
  options.Platform := 'Win32';

  if not TFile.Exists(options.ProjectFile) then
    Assert.Fail('fixture project not found at ' + options.ProjectFile);

  analyzer := TAnalyzer.Create;
  FAnalysis := analyzer.Analyze(options);
end;

function TDuplicateUnitTests.ConflictWarnings : TArray<TScanWarning>;
var
  warning : TScanWarning;
  count : integer;
begin
  SetLength(result, 0);
  count := 0;
  for warning in FAnalysis.Warnings do
    if warning.Message.Contains('DuplicateApp.Shared') and warning.Message.Contains('resolves to') then
    begin
      SetLength(result, count + 1);
      result[count] := warning;
      Inc(count);
    end;
end;

procedure TDuplicateUnitTests.TheFirstCopyFoundIsTheOneKept;
var
  node : TGraphNode;
begin
  // First is named before Second in the dpr, so its copy is found first
  Assert.IsTrue(FAnalysis.Graph.TryFindNode('DuplicateApp.Shared', node), 'Shared is not in the graph');
  Assert.AreEqual(FirstCopy, node.FileName);
end;

procedure TDuplicateUnitTests.TheCopyKeptIsTheCopyRead;
var
  edge : TGraphEdge;
  edges : IReadOnlyList<TGraphEdge>;
begin
  edges := FAnalysis.Graph.EdgesFrom('DuplicateApp.Shared');
  Assert.AreEqual(1, edges.Count, 'each copy of Shared uses exactly one unit');
  edge := edges[0];
  Assert.AreEqual('DuplicateApp.FromFirst', edge.ToUnit);
  Assert.AreEqual(FirstCopy, edge.FileName);
end;

procedure TDuplicateUnitTests.TheOtherCopyIsNotRead;
begin
  Assert.IsFalse(FAnalysis.Graph.ContainsNode('DuplicateApp.FromSecond'),
    'only the copy the graph keeps should be read');
end;

procedure TDuplicateUnitTests.TheOtherCopyIsWarnedAboutOnce;
begin
  // both Second and SecondToo find the other copy, but it is one problem, not two
  Assert.AreEqual<integer>(1, Length(ConflictWarnings));
end;

procedure TDuplicateUnitTests.TheWarningNamesBothCopies;
var
  warnings : TArray<TScanWarning>;
begin
  warnings := ConflictWarnings;
  Assert.AreEqual<integer>(1, Length(warnings));
  Assert.Contains(warnings[0].Message, FirstCopy);
  Assert.Contains(warnings[0].Message, SecondCopy);
end;

procedure TDuplicateUnitTests.TheWarningIsWhereTheOtherCopyWasFound;
var
  warnings : TArray<TScanWarning>;
  edge : TGraphEdge;
  line : integer;
begin
  line := 0;
  for edge in FAnalysis.Graph.EdgesTo('DuplicateApp.Shared') do
    if SameText(edge.FromUnit, 'DuplicateApp.Second') then
      line := edge.Line;

  warnings := ConflictWarnings;
  Assert.AreEqual<integer>(1, Length(warnings));
  Assert.AreEqual(TPath.Combine(DuplicateFixtureFolder, 'Second\DuplicateApp.Second.pas'),
    warnings[0].FileName);
  Assert.AreEqual(line, warnings[0].Line);
end;

{ TOneCopyTests }

function OneCopyFixtureFolder : string;
begin
  result := TPath.GetFullPath(TPath.Combine(ExtractFilePath(ParamStr(0)),
    '..\..\TestData\OneCopyApp'));
end;

procedure TOneCopyTests.Setup;
var
  analyzer : IAnalyzer;
  options : TAnalyzerOptions;
  environment : IDelphiEnvironment;
begin
  environment := TDelphiEnvironment.Create;
  if environment.NewestInstalled = cvUnknown then
    Assert.Pass('no Delphi installed, so the project cannot be prepared');

  options := Default(TAnalyzerOptions);
  options.ProjectFile := TPath.Combine(OneCopyFixtureFolder, 'OneCopyApp.dpr');
  options.Platform := 'Win32';
  // the same folder as A's own, spelt differently
  options.ExtraSearchPaths := [TPath.Combine(OneCopyFixtureFolder, 'Lib\..\Lib')];

  if not TFile.Exists(options.ProjectFile) then
    Assert.Fail('fixture project not found at ' + options.ProjectFile);

  analyzer := TAnalyzer.Create;
  FAnalysis := analyzer.Analyze(options);
end;

procedure TOneCopyTests.OneFileReachedTwoWaysIsNotTwoCopies;
var
  warning : TScanWarning;
begin
  for warning in FAnalysis.Warnings do
    Assert.DoesNotContain(warning.Message, 'resolves to');
end;

procedure TOneCopyTests.AFileFoundThroughDotDotIsNamedWithoutIt;
var
  node : TGraphNode;
begin
  Assert.IsTrue(FAnalysis.Graph.TryFindNode('OneCopyApp.B', node), 'B is not in the graph');
  Assert.AreEqual(TPath.Combine(OneCopyFixtureFolder, 'Lib\OneCopyApp.B.pas'), node.FileName);
end;

{ TAnalyzerProgressTests }

function RunWithProgress(const onProgress : TAnalyzerProgress) : IAnalysisResult;
var
  analyzer : IAnalyzer;
  options : TAnalyzerOptions;
begin
  options := Default(TAnalyzerOptions);
  options.ProjectFile := FixtureProject;
  options.Platform := 'Win32';
  options.Config := 'Debug';
  options.OnProgress := onProgress;

  analyzer := TAnalyzer.Create;
  result := analyzer.Analyze(options);
end;

procedure TAnalyzerProgressTests.ReportsEveryPhaseInOrder;
var
  phases : string;
begin
  phases := '';
  RunWithProgress(
    procedure(const phase : TAnalyzerPhase; const scanned : integer; const queued : integer;
              const currentUnit : string)
    begin
      // only note the first time each phase appears, scanning reports per unit
      if (phases = '') or not phases.EndsWith(GetEnumName(TypeInfo(TAnalyzerPhase), Ord(phase))) then
        phases := phases + GetEnumName(TypeInfo(TAnalyzerPhase), Ord(phase));
    end);

  Assert.AreEqual('apReadingProjectapBuildingSearchPathsapScanningapFinished', phases);
end;

procedure TAnalyzerProgressTests.ScannedCountRisesAndEndsAtTheUnitCount;
var
  highest : integer;
  everWentBackwards : boolean;
  previous : integer;
  analysis : IAnalysisResult;
  parsed : integer;
  node : TGraphNode;
begin
  highest := 0;
  previous := 0;
  everWentBackwards := false;

  analysis := RunWithProgress(
    procedure(const phase : TAnalyzerPhase; const scanned : integer; const queued : integer;
              const currentUnit : string)
    begin
      if scanned < previous then
        everWentBackwards := true;
      previous := scanned;
      if scanned > highest then
        highest := scanned;
    end);

  Assert.IsFalse(everWentBackwards, 'the count should only ever go up');

  parsed := 0;
  for node in analysis.Graph.Nodes do
    if node.Parsed then
      Inc(parsed);
  Assert.AreEqual(parsed, highest, 'the final count should be every unit actually read');
end;

procedure TAnalyzerProgressTests.NamesTheUnitItJustRead;
var
  named : string;
begin
  named := '';
  RunWithProgress(
    procedure(const phase : TAnalyzerPhase; const scanned : integer; const queued : integer;
              const currentUnit : string)
    begin
      if (phase = apScanning) and (currentUnit <> '') then
        named := named + currentUnit + ';';
    end);

  Assert.Contains(named, 'SampleApp.Middle');
  Assert.Contains(named, 'SampleApp.Inner');
end;

procedure TAnalyzerProgressTests.AnalysisRunsWithoutAProgressCallback;
begin
  // nil is the normal case for anything that is not a console
  Assert.IsTrue(RunWithProgress(nil).Graph.Nodes.Count > 0);
end;

function ToPhase(const value : string) : TAnalyzerPhase;
const
  EnumLow = Ord(Low(TAnalyzerPhase));
  EnumHigh = Ord(High(TAnalyzerPhase));
var
  ordinal : integer;
begin
  ordinal := GetEnumValue(TypeInfo(TAnalyzerPhase), value);
  if (ordinal < EnumLow) or (ordinal > EnumHigh) then
    raise EArgumentException.CreateFmt('"%s" is not a TAnalyzerPhase name', [value]);
  result := TAnalyzerPhase(ordinal);
end;

procedure TAnalyzerProgressTests.ScanDescriptionReadsSensibly(const phase : string;
  const scanned : integer; const queued : integer; const expected : string);
begin
  Assert.AreEqual(expected, TConsoleReport.ScanDescription(ToPhase(phase), scanned, queued));
end;

initialization
  TDUnitX.RegisterTestFixture(TAnalyzerTests);
  TDUnitX.RegisterTestFixture(TDuplicateUnitTests);
  TDUnitX.RegisterTestFixture(TOneCopyTests);
  TDUnitX.RegisterTestFixture(TAnalyzerProgressTests);

end.
