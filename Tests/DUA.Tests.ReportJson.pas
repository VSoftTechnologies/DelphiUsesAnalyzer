unit DUA.Tests.ReportJson;

interface

uses
  DUnitX.TestFramework,
  DUA.Types,
  DUA.Analyzer;

type
  /// <summary>
  ///   Writing the graph out and reading it back has to be lossless, because --why on a
  ///   saved file must give exactly the same answer as --why on a fresh walk. The
  ///   analysis here is built by hand rather than walked, so these tests pin the format
  ///   itself and do not need Delphi installed.
  /// </summary>
  [TestFixture]
  TJsonReportTests = class
  private
    FFile : string;
    FOriginal : IAnalysisResult;
    FLoaded : IAnalysisResult;
    function BuildAnalysis : IAnalysisResult;
    function LoadedEdgeTo(const toUnit : string) : string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    // --- project metadata ---
    [Test] 
    procedure KeepsTheProjectPaths;
    [Test]
    procedure KeepsTheRootUnit;
    [Test] 
    procedure KeepsTheTargetCompilerPlatformAndConfig;
    [Test] 
    procedure KeepsTheAppTypeAndProjectVersion;

    // --- nodes ---
    [Test] 
    procedure KeepsEveryNode;
    [Test] 
    procedure KeepsNodeFileNames;
    [Test] 
    procedure KeepsNodeKinds;
    [Test] 
    procedure KeepsTheParsedFlag;
    [Test] 
    procedure KeepsNodeAliases;
    [Test] 
    procedure KeepsANodeWithNoFileName;

    // --- edges ---
    [Test] 
    procedure KeepsEveryEdge;
    [Test] 
    procedure KeepsTheSectionAnEdgeCameFrom;
    [Test] 
    procedure KeepsEdgeCertainty;
    [Test] 
    procedure KeepsTheConditionText;
    [Test] 
    procedure KeepsTheFileAndLineOfAnEdge;

    // --- the rest ---
    [Test] 
    procedure KeepsWarnings;
    [Test] 
    procedure KeepsDefines;
    [Test] 
    procedure KeepsSearchPathsAndTheirOrigins;
    [Test] 
    procedure RecomputesTheUnresolvedCount;

    // --- the point of the exercise ---
    [Test] 
    procedure ChainFindingWorksOnALoadedGraph;

    // --- refusing what it cannot read ---
    [Test] 
    procedure MissingFileRaises;
    [Test] 
    procedure MalformedJsonRaises;
    [Test] 
    procedure JsonThatIsNotAGraphRaises;
    [Test] 
    procedure AnUnknownSchemaVersionRaises;
    [Test] 
    procedure AGraphFromAnEarlierSchemaIsRefused;
    [Test] 
    procedure NodesRecordWhereTheUnitCameFromUnderSource;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  Spring.Collections,
  DUA.Defines,
  DUA.Graph,
  DUA.SearchPath,
  DUA.Compiler.Versions,
  DUA.Report.Json;

{ TJsonReportTests }

function TJsonReportTests.BuildAnalysis : IAnalysisResult;
var
  analysis : TAnalysisResult;
  node : TGraphNode;

  procedure GivenEdge(const fromUnit : string; const toUnit : string;
    const section : TUsesSection; const certainty : TEdgeCertainty;
    const condition : string; const line : integer);
  var
    edge : TGraphEdge;
  begin
    edge := Default(TGraphEdge);
    edge.FromUnit := fromUnit;
    edge.ToUnit := toUnit;
    edge.Section := section;
    edge.Certainty := certainty;
    edge.Condition := condition;
    edge.FileName := 'C:\src\' + fromUnit + '.pas';
    edge.Line := line;
    analysis.Graph.AddEdge(edge);
  end;

begin
  analysis := TAnalysisResult.Create;
  result := analysis;

  analysis.ProjectFile := 'C:\src\MyApp.dproj';
  analysis.DprFile := 'C:\src\MyApp.dpr';
  analysis.RootUnit := 'MyApp';
  analysis.Compiler := cvDelphi13;
  analysis.Platform := dpWin32;
  analysis.Config := 'Debug';
  analysis.AppType := 'Console';
  analysis.ProjectVersion := '20.4';

  analysis.Defines := TDefineSet.Create;
  analysis.Defines.Define('MSWINDOWS');
  analysis.Defines.Define('VER370');

  analysis.Resolver := TUnitResolver.Create;
  analysis.Resolver.AddSearchPath('C:\src', uoProject);
  analysis.Resolver.AddSearchPath('C:\cache\pkg\lib\Win32', uoPackage);
  analysis.Resolver.AddSearchPath('E:\emb\Studio\37.0\source\vcl', uoRTL);

  GivenEdge('MyApp', 'Middle', usProgram, ecUnconditional, '', 7);
  GivenEdge('Middle', 'Inner', usImplementation, ecUnconditional, '', 13);
  GivenEdge('Inner', 'Vcl.Graphics', usInterface, ecConditional, 'MSWINDOWS', 42);
  GivenEdge('Inner', 'System.Math', usInterface, ecUnevaluated, 'Declared(Whatever)', 44);
  GivenEdge('Inner', 'NotFoundAnywhere', usInterface, ecUnconditional, '', 46);

  node := analysis.Graph.EnsureNode('MyApp');
  node.Kind := ukProgram;
  node.FileName := 'C:\src\MyApp.dpr';
  node.Parsed := true;

  node := analysis.Graph.EnsureNode('Middle');
  node.Kind := ukProject;
  node.FileName := 'C:\src\Middle.pas';
  node.Parsed := true;

  node := analysis.Graph.EnsureNode('Inner');
  node.Kind := ukProject;
  node.FileName := 'C:\src\Inner.pas';
  node.Parsed := true;

  node := analysis.Graph.EnsureNode('Vcl.Graphics');
  node.Kind := ukRTL;
  node.FileName := 'E:\emb\Studio\37.0\source\vcl\Vcl.Graphics.pas';
  node.Parsed := false;
  node.Aliases.Add('Graphics');

  node := analysis.Graph.EnsureNode('System.Math');
  node.Kind := ukRTL;
  node.FileName := 'E:\emb\Studio\37.0\source\rtl\common\System.Math.pas';
  node.Parsed := false;

  // an unresolved unit has no file at all, which the format has to survive
  node := analysis.Graph.EnsureNode('NotFoundAnywhere');
  node.Kind := ukUnresolved;
  node.FileName := '';
  node.Parsed := false;

  analysis.Warn('C:\src\Inner.pas', 44, 'cannot evaluate {$IF Declared(Whatever)}');
end;

procedure TJsonReportTests.Setup;
begin
  FFile := TPath.Combine(TPath.GetTempPath, 'dua-report-' + TGuid.NewGuid.ToString + '.json');
  FOriginal := BuildAnalysis;
  TJsonReport.WriteToFile(FOriginal, FFile);
  FLoaded := TJsonReport.Load(FFile);
end;

procedure TJsonReportTests.TearDown;
begin
  FOriginal := nil;
  FLoaded := nil;
  if (FFile <> '') and TFile.Exists(FFile) then
    TFile.Delete(FFile);
end;

function TJsonReportTests.LoadedEdgeTo(const toUnit : string) : string;
var
  edge : TGraphEdge;
begin
  result := '';
  for edge in FLoaded.Graph.Edges do
    if SameText(edge.ToUnit, toUnit) then
      Exit(Format('%s|%s|%s|%s|%s|%d', [edge.FromUnit, edge.ToUnit,
        UsesSectionToString(edge.Section), EdgeCertaintyToString(edge.Certainty),
        edge.Condition, edge.Line]));
end;

procedure TJsonReportTests.KeepsTheProjectPaths;
begin
  Assert.AreEqual('C:\src\MyApp.dproj', FLoaded.ProjectFile);
  Assert.AreEqual('C:\src\MyApp.dpr', FLoaded.DprFile);
end;

procedure TJsonReportTests.KeepsTheRootUnit;
begin
  Assert.AreEqual('MyApp', FLoaded.RootUnit);
end;

procedure TJsonReportTests.KeepsTheTargetCompilerPlatformAndConfig;
begin
  Assert.AreEqual(TCompilerVersions.ToDpmToken(cvDelphi13),
    TCompilerVersions.ToDpmToken(FLoaded.Compiler));
  Assert.AreEqual('Win32', TDelphiPlatforms.ToName(FLoaded.Platform));
  Assert.AreEqual('Debug', FLoaded.Config);
end;

procedure TJsonReportTests.KeepsTheAppTypeAndProjectVersion;
begin
  // both are shown in the header, so a saved graph has to describe itself the same way
  Assert.AreEqual('Console', FLoaded.AppType);
  Assert.AreEqual('20.4', FLoaded.ProjectVersion);
end;

procedure TJsonReportTests.KeepsEveryNode;
begin
  Assert.AreEqual<integer>(FOriginal.Graph.Nodes.Count, FLoaded.Graph.Nodes.Count);
  Assert.IsTrue(FLoaded.Graph.ContainsNode('Vcl.Graphics'), 'Vcl.Graphics');
  Assert.IsTrue(FLoaded.Graph.ContainsNode('NotFoundAnywhere'), 'NotFoundAnywhere');
end;

procedure TJsonReportTests.KeepsNodeFileNames;
var
  node : TGraphNode;
begin
  Assert.IsTrue(FLoaded.Graph.TryFindNode('Inner', node));
  Assert.AreEqual('C:\src\Inner.pas', node.FileName);
end;

procedure TJsonReportTests.KeepsNodeKinds;
var
  node : TGraphNode;
begin
  FLoaded.Graph.TryFindNode('Vcl.Graphics', node);
  Assert.AreEqual(UnitKindToString(ukRTL), UnitKindToString(node.Kind));

  FLoaded.Graph.TryFindNode('MyApp', node);
  Assert.AreEqual(UnitKindToString(ukProgram), UnitKindToString(node.Kind));
end;

procedure TJsonReportTests.KeepsTheParsedFlag;
var
  node : TGraphNode;
begin
  FLoaded.Graph.TryFindNode('Inner', node);
  Assert.IsTrue(node.Parsed, 'Inner was parsed');

  FLoaded.Graph.TryFindNode('Vcl.Graphics', node);
  Assert.IsFalse(node.Parsed, 'Vcl.Graphics was not');
end;

procedure TJsonReportTests.KeepsNodeAliases;
var
  node : TGraphNode;
begin
  FLoaded.Graph.TryFindNode('Vcl.Graphics', node);
  Assert.AreEqual<integer>(1, node.Aliases.Count);
  Assert.AreEqual('Graphics', node.Aliases[0]);
end;

procedure TJsonReportTests.KeepsANodeWithNoFileName;
var
  node : TGraphNode;
begin
  Assert.IsTrue(FLoaded.Graph.TryFindNode('NotFoundAnywhere', node));
  Assert.AreEqual('', node.FileName);
  Assert.AreEqual(UnitKindToString(ukUnresolved), UnitKindToString(node.Kind));
end;

procedure TJsonReportTests.KeepsEveryEdge;
begin
  Assert.AreEqual<integer>(FOriginal.Graph.Edges.Count, FLoaded.Graph.Edges.Count);
end;

procedure TJsonReportTests.KeepsTheSectionAnEdgeCameFrom;
begin
  Assert.AreEqual('MyApp|Middle|program|unconditional||7', LoadedEdgeTo('Middle'));
  Assert.AreEqual('Middle|Inner|implementation|unconditional||13', LoadedEdgeTo('Inner'));
end;

procedure TJsonReportTests.KeepsEdgeCertainty;
begin
  Assert.Contains(LoadedEdgeTo('Vcl.Graphics'), '|conditional|');
  Assert.Contains(LoadedEdgeTo('System.Math'), '|unevaluated|');
end;

procedure TJsonReportTests.KeepsTheConditionText;
begin
  Assert.Contains(LoadedEdgeTo('Vcl.Graphics'), 'MSWINDOWS');
  Assert.Contains(LoadedEdgeTo('System.Math'), 'Declared(Whatever)');
end;

procedure TJsonReportTests.KeepsTheFileAndLineOfAnEdge;
var
  edge : TGraphEdge;
  found : boolean;
begin
  found := false;
  for edge in FLoaded.Graph.Edges do
    if SameText(edge.ToUnit, 'Vcl.Graphics') then
    begin
      found := true;
      Assert.AreEqual('C:\src\Inner.pas', edge.FileName);
      Assert.AreEqual(42, edge.Line);
    end;
  Assert.IsTrue(found);
end;

procedure TJsonReportTests.KeepsWarnings;
begin
  Assert.AreEqual<integer>(1, FLoaded.Warnings.Count);
  Assert.AreEqual('C:\src\Inner.pas', FLoaded.Warnings[0].FileName);
  Assert.AreEqual(44, FLoaded.Warnings[0].Line);
  Assert.Contains(FLoaded.Warnings[0].Message, 'Declared(Whatever)');
end;

procedure TJsonReportTests.KeepsDefines;
begin
  Assert.IsTrue(FLoaded.Defines.IsDefined('MSWINDOWS'), 'MSWINDOWS');
  Assert.IsTrue(FLoaded.Defines.IsDefined('VER370'), 'VER370');
  Assert.IsFalse(FLoaded.Defines.IsDefined('LINUX'), 'LINUX');
end;

procedure TJsonReportTests.KeepsSearchPathsAndTheirOrigins;
begin
  Assert.AreEqual<integer>(3, FLoaded.Resolver.SearchPaths.Count);
  Assert.AreEqual('C:\src', FLoaded.Resolver.SearchPaths[0].Path);
  Assert.AreEqual(Ord(uoPackage), Ord(FLoaded.Resolver.SearchPaths[1].Origin));
  Assert.AreEqual(Ord(uoRTL), Ord(FLoaded.Resolver.SearchPaths[2].Origin));
end;

procedure TJsonReportTests.RecomputesTheUnresolvedCount;
begin
  Assert.AreEqual(1, FLoaded.UnresolvedCount);
end;

procedure TJsonReportTests.ChainFindingWorksOnALoadedGraph;
var
  chains : IReadOnlyList<TArray<string>>;
begin
  // this is the whole reason for reading a file back rather than walking again
  chains := FLoaded.Graph.FindPaths('MyApp', 'Vcl.Graphics', 5);
  Assert.AreEqual<integer>(1, chains.Count);
  Assert.AreEqual('MyApp>Middle>Inner>Vcl.Graphics', string.Join('>', chains[0]));
end;

procedure TJsonReportTests.MissingFileRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      TJsonReport.Load(TPath.Combine(TPath.GetTempPath, 'dua-no-such-graph-xyzzy.json'));
    end, EJsonReportError);
end;

procedure TJsonReportTests.MalformedJsonRaises;
var
  broken : string;
begin
  broken := TPath.Combine(TPath.GetTempPath, 'dua-broken-' + TGuid.NewGuid.ToString + '.json');
  TFile.WriteAllText(broken, '{ "schemaVersion" : 1, "nodes" : [ ');
  try
    Assert.WillRaise(
      procedure
      begin
        TJsonReport.Load(broken);
      end, EJsonReportError);
  finally
    TFile.Delete(broken);
  end;
end;

procedure TJsonReportTests.JsonThatIsNotAGraphRaises;
var
  other : string;
begin
  other := TPath.Combine(TPath.GetTempPath, 'dua-other-' + TGuid.NewGuid.ToString + '.json');
  TFile.WriteAllText(other, '{ "name" : "something else entirely" }');
  try
    Assert.WillRaise(
      procedure
      begin
        TJsonReport.Load(other);
      end, EJsonReportError);
  finally
    TFile.Delete(other);
  end;
end;

procedure TJsonReportTests.AnUnknownSchemaVersionRaises;
var
  future : string;
begin
  // better to refuse than to quietly misread a format we do not understand
  future := TPath.Combine(TPath.GetTempPath, 'dua-future-' + TGuid.NewGuid.ToString + '.json');
  TFile.WriteAllText(future, '{ "schemaVersion" : 99, "nodes" : [], "edges" : [] }');
  try
    Assert.WillRaise(
      procedure
      begin
        TJsonReport.Load(future);
      end, EJsonReportError);
  finally
    TFile.Delete(future);
  end;
end;

procedure TJsonReportTests.AGraphFromAnEarlierSchemaIsRefused;
var
  old : string;
begin
  // version 1 called this field "kind"; reading it as though it were current would
  // leave every unit unclassified rather than saying so
  old := TPath.Combine(TPath.GetTempPath, 'dua-v1-' + TGuid.NewGuid.ToString + '.json');
  TFile.WriteAllText(old,
    '{ "schemaVersion" : 1, "nodes" : [ { "name" : "A", "kind" : "rtl" } ], "edges" : [] }');
  try
    Assert.WillRaise(
      procedure
      begin
        TJsonReport.Load(old);
      end, EJsonReportError);
  finally
    TFile.Delete(old);
  end;
end;

procedure TJsonReportTests.NodesRecordWhereTheUnitCameFromUnderSource;
var
  written : string;
begin
  written := TFile.ReadAllText(FFile);
  Assert.Contains(written, '"source"', 'a node should say where it came from');
  Assert.DoesNotContain(written, '"kind"', 'the old field name should be gone');
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonReportTests);

end.
