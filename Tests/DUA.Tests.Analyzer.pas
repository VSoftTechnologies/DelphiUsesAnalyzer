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

procedure TAnalyzerProgressTests.ScanDescriptionReadsSensibly(const phase : string;
  const scanned : integer; const queued : integer; const expected : string);
begin
  Assert.AreEqual(expected, TConsoleReport.ScanDescription(
    TAnalyzerPhase(GetEnumValue(TypeInfo(TAnalyzerPhase), phase)), scanned, queued));
end;

initialization
  TDUnitX.RegisterTestFixture(TAnalyzerTests);
  TDUnitX.RegisterTestFixture(TAnalyzerProgressTests);

end.
