unit DUA.Tests.Graph;

interface

uses
  DUnitX.TestFramework,
  DUA.Types,
  DUA.Graph;

type
  [TestFixture]
  TUnitGraphTests = class
  private
    FGraph : IUnitGraph;
    procedure GivenEdge(const fromUnit : string; const toUnit : string);
    function ChainsFrom(const fromUnit : string; const toUnit : string) : string;
  public
    [Setup]
    procedure Setup;

    // --- nodes ---
    [Test] procedure EnsureNodeCreatesTheNode;
    [Test] procedure EnsureNodeReturnsTheSameNodeTwice;
    [Test] procedure NodeLookupIsCaseInsensitive;
    [Test] procedure NodeKeepsTheCasingItWasFirstCreatedWith;
    [Test] procedure MissingNodeIsNotFound;

    // --- lookup by name or glob, which is what --why takes ---
    [Test] procedure FindNodesReturnsAnExactMatch;
    [Test] procedure FindNodesIsCaseInsensitive;
    [Test] procedure FindNodesReturnsNothingForAnUnknownName;
    [Test] procedure FindNodesDoesNotMatchOnAPrefixWithoutAWildcard;
    [Test] procedure FindNodesMatchesAGlob;
    [Test] procedure FindNodesReturnsMatchesSortedByName;
    [Test] procedure FindNodesMatchesEverythingForAStar;
    [Test] procedure FindNodesMatchesAnAlias;
    [Test] procedure FindNodesReturnsEachNodeOnceEvenWithAliases;

    // --- edges ---
    [Test] procedure AddingAnEdgeCreatesBothNodes;
    [Test] procedure IdenticalEdgesAreOnlyStoredOnce;
    [Test] procedure EdgesDifferingBySectionAreBothKept;
    [Test] procedure EdgesDifferingByTargetAreBothKept;

    // --- adjacency ---
    [Test] procedure DependenciesListsWhatAUnitUses;
    [Test] procedure DependentsListsWhoUsesAUnit;
    [Test] procedure DependentsIsEmptyForTheRoot;
    [Test] procedure AdjacencyLookupIsCaseInsensitive;
    [Test] procedure TheSameUnitSpeltTwoWaysIsOneDependency;
    [Test] procedure TheSameUnitSpeltTwoWaysIsOneDependent;

    // --- what the references command is built on ---
    [Test] procedure EdgesToGivesEveryArrivingEdge;
    [Test] procedure EdgesToCarriesTheSectionFileAndLine;
    [Test] procedure EdgesToKeepsBothSectionsOfTheSameUnit;
    [Test] procedure EdgesToIsEmptyForAUnitNothingReferences;
    [Test] procedure EdgesToIsCaseInsensitive;

    // --- what the cost and deps commands are built on ---
    [Test] procedure EdgesFromGivesEveryLeavingEdge;
    [Test] procedure EdgesFromCarriesTheSectionFileAndLine;
    [Test] procedure EdgesFromKeepsBothSectionsOfTheSameUnit;
    [Test] procedure EdgesFromIsEmptyForAUnitThatUsesNothing;
    [Test] procedure EdgesFromIsCaseInsensitive;

    // --- reachability ---
    [Test] procedure ReachableFromIncludesTheUnitItself;
    [Test] procedure ReachableFromFollowsTheWholeChain;
    [Test] procedure ReachableFromLeavesOutWhatItCannotReach;
    [Test] procedure ReachableFromCountsAUnitOnceHoweverManyRoutesReachIt;
    [Test] procedure ReachableFromIsEmptyForAnUnknownUnit;
    [Test] procedure ReachableFromSurvivesACycle;

    // --- path finding, which is what --why is built on ---
    [Test] procedure FindsADirectChain;
    [Test] procedure FindsAChainThroughIntermediates;
    [Test] procedure ReturnsTheShortestChain;
    [Test] procedure ReturnsNothingWhenThereIsNoRoute;
    [Test] procedure ReturnsNothingWhenTheTargetIsUnknown;
    [Test] procedure ACycleDoesNotHangTheSearch;
    [Test] procedure FindsSeveralDistinctChains;
    [Test] procedure RespectsTheMaximumNumberOfChains;
    [Test] procedure AChainFromAUnitToItselfIsJustThatUnit;
    [Test] procedure AskingTwiceGivesTheSameAnswer;
    [Test] procedure AnEdgeAddedAfterAQueryIsTakenIntoAccount;
    [Test] procedure ADifferentStartingPointGetsItsOwnAnswer;
  end;

implementation

uses
  System.SysUtils,
  Spring.Collections;

{ TUnitGraphTests }

procedure TUnitGraphTests.Setup;
begin
  FGraph := TUnitGraph.Create;
end;

procedure TUnitGraphTests.GivenEdge(const fromUnit : string; const toUnit : string);
var
  edge : TGraphEdge;
begin
  edge := Default(TGraphEdge);
  edge.FromUnit := fromUnit;
  edge.ToUnit := toUnit;
  edge.Section := usInterface;
  edge.Certainty := ecUnconditional;
  FGraph.AddEdge(edge);
end;

/// <summary>Renders the found chains as "A>B>C|A>D>C" so a test can assert on them.</summary>
function TUnitGraphTests.ChainsFrom(const fromUnit : string; const toUnit : string) : string;
var
  chains : IReadOnlyList<TArray<string>>;
  chain : TArray<string>;
begin
  result := '';
  chains := FGraph.FindPaths(fromUnit, toUnit, 10);
  for chain in chains do
  begin
    if result <> '' then
      result := result + '|';
    result := result + string.Join('>', chain);
  end;
end;

procedure TUnitGraphTests.EnsureNodeCreatesTheNode;
begin
  FGraph.EnsureNode('MyUnit');
  Assert.IsTrue(FGraph.ContainsNode('MyUnit'));
  Assert.AreEqual<integer>(1, FGraph.Nodes.Count);
end;

procedure TUnitGraphTests.EnsureNodeReturnsTheSameNodeTwice;
begin
  Assert.AreSame(FGraph.EnsureNode('MyUnit'), FGraph.EnsureNode('MyUnit'));
  Assert.AreEqual<integer>(1, FGraph.Nodes.Count);
end;

procedure TUnitGraphTests.NodeLookupIsCaseInsensitive;
begin
  FGraph.EnsureNode('System.Classes');
  Assert.IsTrue(FGraph.ContainsNode('SYSTEM.CLASSES'));
  Assert.AreSame(FGraph.EnsureNode('System.Classes'), FGraph.EnsureNode('system.classes'));
end;

procedure TUnitGraphTests.NodeKeepsTheCasingItWasFirstCreatedWith;
begin
  FGraph.EnsureNode('System.Classes');
  Assert.AreEqual('System.Classes', FGraph.EnsureNode('SYSTEM.CLASSES').Name);
end;

procedure TUnitGraphTests.MissingNodeIsNotFound;
var
  node : TGraphNode;
begin
  Assert.IsFalse(FGraph.TryFindNode('NoSuchUnit', node));
  Assert.IsNull(node);
end;

function NamesOf(const nodes : IReadOnlyList<TGraphNode>) : string;
var
  node : TGraphNode;
begin
  result := '';
  for node in nodes do
  begin
    if result <> '' then
      result := result + ',';
    result := result + node.Name;
  end;
end;

/// <summary>Renders a list of names as "A,B,C" so a test can assert on the order too.</summary>
function Joined(const names : IReadOnlyList<string>) : string;
begin
  result := string.Join(',', names.ToArray);
end;

procedure TUnitGraphTests.FindNodesReturnsAnExactMatch;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  Assert.AreEqual('Vcl.Forms', NamesOf(FGraph.FindNodes('Vcl.Forms')));
end;

procedure TUnitGraphTests.FindNodesIsCaseInsensitive;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  Assert.AreEqual('Vcl.Forms', NamesOf(FGraph.FindNodes('vcl.FORMS')));
end;

procedure TUnitGraphTests.FindNodesReturnsNothingForAnUnknownName;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  Assert.AreEqual('', NamesOf(FGraph.FindNodes('NoSuchUnit')));
end;

procedure TUnitGraphTests.FindNodesDoesNotMatchOnAPrefixWithoutAWildcard;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  Assert.AreEqual('', NamesOf(FGraph.FindNodes('Vcl')), 'a plain name is not a prefix search');
end;

procedure TUnitGraphTests.FindNodesMatchesAGlob;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  GivenEdge('MyApp', 'Vcl.Graphics');
  GivenEdge('MyApp', 'System.Classes');

  Assert.AreEqual('Vcl.Forms,Vcl.Graphics', NamesOf(FGraph.FindNodes('Vcl.*')));
end;

procedure TUnitGraphTests.FindNodesReturnsMatchesSortedByName;
begin
  GivenEdge('MyApp', 'Vcl.Graphics');
  GivenEdge('MyApp', 'Vcl.ComCtrls');
  GivenEdge('MyApp', 'Vcl.Forms');

  Assert.AreEqual('Vcl.ComCtrls,Vcl.Forms,Vcl.Graphics', NamesOf(FGraph.FindNodes('Vcl.*')));
end;

procedure TUnitGraphTests.FindNodesMatchesEverythingForAStar;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  Assert.AreEqual<integer>(2, FGraph.FindNodes('*').Count);
end;

procedure TUnitGraphTests.FindNodesMatchesAnAlias;
begin
  GivenEdge('MyApp', 'System.Classes');
  FGraph.EnsureNode('System.Classes').Aliases.Add('Classes');

  // the source said Classes, so that is a reasonable thing to ask about
  Assert.AreEqual('System.Classes', NamesOf(FGraph.FindNodes('Classes')));
end;

procedure TUnitGraphTests.FindNodesReturnsEachNodeOnceEvenWithAliases;
begin
  GivenEdge('MyApp', 'System.Classes');
  FGraph.EnsureNode('System.Classes').Aliases.Add('Classes');
  FGraph.EnsureNode('System.Classes').Aliases.Add('Clashes');

  Assert.AreEqual<integer>(1, FGraph.FindNodes('Cla*').Count,
    'a node matching by name and by alias is still one node');
end;

procedure TUnitGraphTests.AddingAnEdgeCreatesBothNodes;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  Assert.IsTrue(FGraph.ContainsNode('MyApp'), 'MyApp');
  Assert.IsTrue(FGraph.ContainsNode('Vcl.Forms'), 'Vcl.Forms');
end;

procedure TUnitGraphTests.IdenticalEdgesAreOnlyStoredOnce;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  GivenEdge('MyApp', 'Vcl.Forms');
  Assert.AreEqual<integer>(1, FGraph.Edges.Count);
end;

procedure TUnitGraphTests.EdgesDifferingBySectionAreBothKept;
var
  edge : TGraphEdge;
begin
  GivenEdge('MyUnit', 'System.Classes');

  edge := Default(TGraphEdge);
  edge.FromUnit := 'MyUnit';
  edge.ToUnit := 'System.Classes';
  edge.Section := usImplementation;
  FGraph.AddEdge(edge);

  Assert.AreEqual<integer>(2, FGraph.Edges.Count,
    'a unit used in both sections is two different facts');
end;

procedure TUnitGraphTests.EdgesDifferingByTargetAreBothKept;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  GivenEdge('MyApp', 'System.Classes');
  Assert.AreEqual<integer>(2, FGraph.Edges.Count);
end;

procedure TUnitGraphTests.DependenciesListsWhatAUnitUses;
var
  dependencies : IReadOnlyList<string>;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('MyApp', 'UnitB');

  dependencies := FGraph.Dependencies('MyApp');
  Assert.AreEqual<integer>(2, dependencies.Count);
  Assert.IsTrue(dependencies.Contains('UnitA'), 'UnitA');
  Assert.IsTrue(dependencies.Contains('UnitB'), 'UnitB');
end;

procedure TUnitGraphTests.DependentsListsWhoUsesAUnit;
var
  dependents : IReadOnlyList<string>;
begin
  GivenEdge('UnitA', 'Vcl.Forms');
  GivenEdge('UnitB', 'Vcl.Forms');

  dependents := FGraph.Dependents('Vcl.Forms');
  Assert.AreEqual<integer>(2, dependents.Count);
  Assert.IsTrue(dependents.Contains('UnitA'), 'UnitA');
  Assert.IsTrue(dependents.Contains('UnitB'), 'UnitB');
end;

procedure TUnitGraphTests.DependentsIsEmptyForTheRoot;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual<integer>(0, FGraph.Dependents('MyApp').Count);
end;

procedure TUnitGraphTests.AdjacencyLookupIsCaseInsensitive;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  Assert.AreEqual<integer>(1, FGraph.Dependencies('MYAPP').Count);
  Assert.AreEqual<integer>(1, FGraph.Dependents('vcl.forms').Count);
end;

procedure TUnitGraphTests.EdgesToGivesEveryArrivingEdge;
begin
  GivenEdge('UnitA', 'Vcl.Forms');
  GivenEdge('UnitB', 'Vcl.Forms');
  GivenEdge('UnitC', 'System.Classes');

  Assert.AreEqual<integer>(2, FGraph.EdgesTo('Vcl.Forms').Count);
  Assert.AreEqual('UnitA', FGraph.EdgesTo('Vcl.Forms')[0].FromUnit);
  Assert.AreEqual('UnitB', FGraph.EdgesTo('Vcl.Forms')[1].FromUnit);
end;

procedure TUnitGraphTests.EdgesToCarriesTheSectionFileAndLine;
var
  edge : TGraphEdge;
begin
  edge := Default(TGraphEdge);
  edge.FromUnit := 'UnitA';
  edge.ToUnit := 'Vcl.Forms';
  edge.Section := usImplementation;
  edge.Certainty := ecConditional;
  edge.Condition := 'MSWINDOWS';
  edge.FileName := 'C:\src\UnitA.pas';
  edge.Line := 42;
  FGraph.AddEdge(edge);

  // the point of references is being able to go and look at the line
  Assert.AreEqual('C:\src\UnitA.pas', FGraph.EdgesTo('Vcl.Forms')[0].FileName);
  Assert.AreEqual(42, FGraph.EdgesTo('Vcl.Forms')[0].Line);
  Assert.AreEqual(UsesSectionToString(usImplementation),
    UsesSectionToString(FGraph.EdgesTo('Vcl.Forms')[0].Section));
  Assert.AreEqual('MSWINDOWS', FGraph.EdgesTo('Vcl.Forms')[0].Condition);
end;

procedure TUnitGraphTests.EdgesToKeepsBothSectionsOfTheSameUnit;
var
  edge : TGraphEdge;
begin
  GivenEdge('UnitA', 'System.Classes');

  edge := Default(TGraphEdge);
  edge.FromUnit := 'UnitA';
  edge.ToUnit := 'System.Classes';
  edge.Section := usImplementation;
  FGraph.AddEdge(edge);

  Assert.AreEqual<integer>(2, FGraph.EdgesTo('System.Classes').Count,
    'a unit that uses another from both sections references it twice');
end;

procedure TUnitGraphTests.EdgesToIsEmptyForAUnitNothingReferences;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual<integer>(0, FGraph.EdgesTo('MyApp').Count);
  Assert.AreEqual<integer>(0, FGraph.EdgesTo('NoSuchUnit').Count);
end;

procedure TUnitGraphTests.EdgesToIsCaseInsensitive;
begin
  GivenEdge('UnitA', 'Vcl.Forms');
  Assert.AreEqual<integer>(1, FGraph.EdgesTo('VCL.FORMS').Count);
end;

procedure TUnitGraphTests.EdgesFromGivesEveryLeavingEdge;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('MyApp', 'UnitB');
  GivenEdge('Other', 'UnitC');

  Assert.AreEqual<integer>(2, FGraph.EdgesFrom('MyApp').Count);
  Assert.AreEqual('UnitA', FGraph.EdgesFrom('MyApp')[0].ToUnit);
  Assert.AreEqual('UnitB', FGraph.EdgesFrom('MyApp')[1].ToUnit);
end;

procedure TUnitGraphTests.EdgesFromCarriesTheSectionFileAndLine;
var
  edge : TGraphEdge;
begin
  edge := Default(TGraphEdge);
  edge.FromUnit := 'UnitA';
  edge.ToUnit := 'Vcl.Forms';
  edge.Section := usImplementation;
  edge.Certainty := ecConditional;
  edge.Condition := 'MSWINDOWS';
  edge.FileName := 'C:\src\UnitA.pas';
  edge.Line := 42;
  FGraph.AddEdge(edge);

  // cost names the uses entry to delete, so it needs the line it was written on
  Assert.AreEqual('C:\src\UnitA.pas', FGraph.EdgesFrom('UnitA')[0].FileName);
  Assert.AreEqual(42, FGraph.EdgesFrom('UnitA')[0].Line);
  Assert.AreEqual(UsesSectionToString(usImplementation),
    UsesSectionToString(FGraph.EdgesFrom('UnitA')[0].Section));
  Assert.AreEqual('MSWINDOWS', FGraph.EdgesFrom('UnitA')[0].Condition);
end;

procedure TUnitGraphTests.EdgesFromKeepsBothSectionsOfTheSameUnit;
var
  edge : TGraphEdge;
begin
  GivenEdge('UnitA', 'System.Classes');

  edge := Default(TGraphEdge);
  edge.FromUnit := 'UnitA';
  edge.ToUnit := 'System.Classes';
  edge.Section := usImplementation;
  FGraph.AddEdge(edge);

  Assert.AreEqual<integer>(2, FGraph.EdgesFrom('UnitA').Count,
    'both clauses are entries someone could go and delete');
end;

procedure TUnitGraphTests.EdgesFromIsEmptyForAUnitThatUsesNothing;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual<integer>(0, FGraph.EdgesFrom('UnitA').Count);
  Assert.AreEqual<integer>(0, FGraph.EdgesFrom('NoSuchUnit').Count);
end;

procedure TUnitGraphTests.EdgesFromIsCaseInsensitive;
begin
  GivenEdge('UnitA', 'Vcl.Forms');
  Assert.AreEqual<integer>(1, FGraph.EdgesFrom('UNITA').Count);
end;

procedure TUnitGraphTests.ReachableFromIncludesTheUnitItself;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual('MyApp,UnitA', Joined(FGraph.ReachableFrom('MyApp')));
end;

procedure TUnitGraphTests.ReachableFromFollowsTheWholeChain;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Inner');
  GivenEdge('Inner', 'Vcl.Forms');

  // nearest first, because that is the order the search reaches them in
  Assert.AreEqual('MyApp,Middle,Inner,Vcl.Forms', Joined(FGraph.ReachableFrom('MyApp')));
end;

procedure TUnitGraphTests.ReachableFromLeavesOutWhatItCannotReach;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('Orphan', 'UnitB');

  Assert.AreEqual('MyApp,UnitA', Joined(FGraph.ReachableFrom('MyApp')));
end;

procedure TUnitGraphTests.ReachableFromCountsAUnitOnceHoweverManyRoutesReachIt;
begin
  GivenEdge('MyApp', 'Left');
  GivenEdge('MyApp', 'Right');
  GivenEdge('Left', 'Shared');
  GivenEdge('Right', 'Shared');

  Assert.AreEqual<integer>(4, FGraph.ReachableFrom('MyApp').Count);
end;

procedure TUnitGraphTests.ReachableFromIsEmptyForAnUnknownUnit;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual<integer>(0, FGraph.ReachableFrom('NoSuchUnit').Count);
end;

procedure TUnitGraphTests.ReachableFromSurvivesACycle;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitA');

  Assert.AreEqual<integer>(3, FGraph.ReachableFrom('MyApp').Count);
end;

procedure TUnitGraphTests.TheSameUnitSpeltTwoWaysIsOneDependency;
var
  edge : TGraphEdge;
begin
  // A unit used from both clauses is two edges, and the two clauses can spell it
  // differently. It is still one unit, and counting it twice would inflate every
  // reachability answer built on this.
  GivenEdge('MyApp', 'Winapi.Windows');

  edge := Default(TGraphEdge);
  edge.FromUnit := 'MyApp';
  edge.ToUnit := 'WinAPi.WINDOWS';
  edge.Section := usImplementation;
  FGraph.AddEdge(edge);

  Assert.AreEqual<integer>(2, FGraph.EdgesFrom('MyApp').Count, 'both clauses are edges');
  Assert.AreEqual<integer>(1, FGraph.Dependencies('MyApp').Count, 'but only one unit');
end;

procedure TUnitGraphTests.TheSameUnitSpeltTwoWaysIsOneDependent;
var
  edge : TGraphEdge;
begin
  GivenEdge('Winapi.Windows', 'MyApp');

  edge := Default(TGraphEdge);
  edge.FromUnit := 'WinAPi.WINDOWS';
  edge.ToUnit := 'MyApp';
  edge.Section := usImplementation;
  FGraph.AddEdge(edge);

  Assert.AreEqual<integer>(1, FGraph.Dependents('MyApp').Count);
end;

procedure TUnitGraphTests.FindsADirectChain;
begin
  GivenEdge('MyApp', 'Vcl.Forms');
  Assert.AreEqual('MyApp>Vcl.Forms', ChainsFrom('MyApp', 'Vcl.Forms'));
end;

procedure TUnitGraphTests.FindsAChainThroughIntermediates;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Inner');
  GivenEdge('Inner', 'Vcl.Forms');

  Assert.AreEqual('MyApp>Middle>Inner>Vcl.Forms', ChainsFrom('MyApp', 'Vcl.Forms'));
end;

procedure TUnitGraphTests.ReturnsTheShortestChain;
begin
  GivenEdge('MyApp', 'Short');
  GivenEdge('Short', 'Vcl.Forms');
  GivenEdge('MyApp', 'Long1');
  GivenEdge('Long1', 'Long2');
  GivenEdge('Long2', 'Vcl.Forms');

  Assert.AreEqual('MyApp>Short>Vcl.Forms', ChainsFrom('MyApp', 'Vcl.Forms'));
end;

procedure TUnitGraphTests.ReturnsNothingWhenThereIsNoRoute;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('Unrelated', 'Vcl.Forms');

  Assert.AreEqual('', ChainsFrom('MyApp', 'Vcl.Forms'));
end;

procedure TUnitGraphTests.ReturnsNothingWhenTheTargetIsUnknown;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual('', ChainsFrom('MyApp', 'NeverHeardOfIt'));
end;

procedure TUnitGraphTests.ACycleDoesNotHangTheSearch;
begin
  // mutually recursive implementation uses clauses are legal and common
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitA');
  GivenEdge('UnitB', 'Vcl.Forms');

  Assert.AreEqual('MyApp>UnitA>UnitB>Vcl.Forms', ChainsFrom('MyApp', 'Vcl.Forms'));
end;

procedure TUnitGraphTests.FindsSeveralDistinctChains;
var
  chains : string;
begin
  GivenEdge('MyApp', 'Left');
  GivenEdge('MyApp', 'Right');
  GivenEdge('Left', 'Vcl.Forms');
  GivenEdge('Right', 'Vcl.Forms');

  chains := ChainsFrom('MyApp', 'Vcl.Forms');
  Assert.Contains(chains, 'MyApp>Left>Vcl.Forms');
  Assert.Contains(chains, 'MyApp>Right>Vcl.Forms');
end;

procedure TUnitGraphTests.RespectsTheMaximumNumberOfChains;
begin
  GivenEdge('MyApp', 'A');
  GivenEdge('MyApp', 'B');
  GivenEdge('MyApp', 'C');
  GivenEdge('A', 'Target');
  GivenEdge('B', 'Target');
  GivenEdge('C', 'Target');

  Assert.AreEqual<integer>(2, FGraph.FindPaths('MyApp', 'Target', 2).Count);
end;

procedure TUnitGraphTests.AChainFromAUnitToItselfIsJustThatUnit;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual('MyApp', ChainsFrom('MyApp', 'MyApp'));
end;

procedure TUnitGraphTests.AskingTwiceGivesTheSameAnswer;
begin
  // the search from a given start is reused across targets, so it has to stay correct
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Vcl.Forms');
  GivenEdge('Middle', 'Vcl.Graphics');

  Assert.AreEqual('MyApp>Middle>Vcl.Forms', ChainsFrom('MyApp', 'Vcl.Forms'));
  Assert.AreEqual('MyApp>Middle>Vcl.Graphics', ChainsFrom('MyApp', 'Vcl.Graphics'));
  Assert.AreEqual('MyApp>Middle>Vcl.Forms', ChainsFrom('MyApp', 'Vcl.Forms'));
end;

procedure TUnitGraphTests.AnEdgeAddedAfterAQueryIsTakenIntoAccount;
begin
  GivenEdge('MyApp', 'Long1');
  GivenEdge('Long1', 'Long2');
  GivenEdge('Long2', 'Target');
  Assert.AreEqual('MyApp>Long1>Long2>Target', ChainsFrom('MyApp', 'Target'));

  // a shorter route appears, and the previous answer must not be reused
  GivenEdge('MyApp', 'Target');
  Assert.AreEqual('MyApp>Target', ChainsFrom('MyApp', 'Target'));
end;

procedure TUnitGraphTests.ADifferentStartingPointGetsItsOwnAnswer;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Target');

  Assert.AreEqual('MyApp>Middle>Target', ChainsFrom('MyApp', 'Target'));
  Assert.AreEqual('Middle>Target', ChainsFrom('Middle', 'Target'));
  Assert.AreEqual('MyApp>Middle>Target', ChainsFrom('MyApp', 'Target'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitGraphTests);

end.
