unit DUA.Tests.GraphAnalysis;

interface

uses
  DUnitX.TestFramework,
  DUA.Types,
  DUA.Graph,
  DUA.Graph.Analysis;

type
  [TestFixture]
  TDominatorTests = class
  private
    FGraph : IUnitGraph;
    procedure GivenEdge(const fromUnit : string; const toUnit : string);
    function Tree : IDominatorTree;
  public
    [Setup]
    procedure Setup;

    // --- what dominates what ---
    [Test] procedure TheRootDominatesNothingAboveIt;
    [Test] procedure AChainMakesEveryUnitDominateTheNext;
    [Test] procedure AUnitReachedTwoWaysIsDominatedByWhereTheRoutesPart;
    [Test] procedure AUnitReachedOneWayIsDominatedByThatRoute;
    [Test] procedure ACycleDoesNotStopTheSearch;
    [Test] procedure LookupIsCaseInsensitive;

    // --- reachability ---
    [Test] procedure AnUnreachableUnitIsReportedAsSuch;
    [Test] procedure AnUnreachableUnitHasNoDominator;
    [Test] procedure AnUnknownRootGivesAnEmptyTree;
    [Test] procedure ReachableCountIncludesTheRoot;

    // --- how much a unit exclusively brings in ---
    [Test] procedure ExclusiveReachOfALeafIsOne;
    [Test] procedure ExclusiveReachCountsEverythingOnlyItReaches;
    [Test] procedure ExclusiveReachExcludesWhatIsReachableAnotherWay;
    [Test] procedure ExclusiveReachOfTheRootIsTheWholeGraph;
    [Test] procedure ExclusiveReachOfAnUnreachableUnitIsZero;
  end;

  [TestFixture]
  TCycleTests = class
  private
    FGraph : IUnitGraph;
    procedure GivenEdge(const fromUnit : string; const toUnit : string);
  public
    [Setup]
    procedure Setup;

    [Test] procedure AGraphWithoutCyclesHasNone;
    [Test] procedure ADiamondIsNotACycle;
    [Test] procedure TwoUnitsUsingEachOtherAreAGroup;
    [Test] procedure AThreeUnitLoopIsOneGroup;
    [Test] procedure TwoSeparateLoopsAreTwoGroups;
    [Test] procedure TheLargestGroupComesFirst;
    [Test] procedure AUnitOutsideTheLoopIsNotInTheGroup;
    [Test] procedure TheRoundTripShowsHowTheLoopCloses;
    [Test] procedure TheRoundTripIsTheShortestOne;
    [Test] procedure TheRoundTripOfAGroupOfOneIsEmpty;
  end;

  [TestFixture]
  TReachTests = class
  private
    FGraph : IUnitGraph;
    procedure GivenEdge(const fromUnit : string; const toUnit : string);
  public
    [Setup]
    procedure Setup;

    [Test] procedure CountFromIncludesTheStart;
    [Test] procedure CountFromFollowsTheWholeChain;
    [Test] procedure CountFromIsZeroForAnUnknownUnit;
    [Test] procedure RemovingAnEdgeDropsWhatOnlyItReached;
    [Test] procedure RemovingAnEdgeDropsNothingWhenThereIsAnotherRoute;
    [Test] procedure RemovingAnEdgeThatIsNotThereChangesNothing;
    [Test] procedure ACycleDoesNotHangTheCount;
  end;

  [TestFixture]
  TGraphDiffTests = class
  private
    FBefore : IUnitGraph;
    FAfter : IUnitGraph;
    procedure GivenEdge(const graph : IUnitGraph; const fromUnit : string;
                        const toUnit : string);
  public
    [Setup]
    procedure Setup;

    [Test] procedure TwoIdenticalGraphsDifferInNothing;
    [Test] procedure AUnitOnlyInTheSecondIsAnAddition;
    [Test] procedure AUnitOnlyInTheFirstIsARemoval;
    [Test] procedure AnEdgeOnlyInTheSecondIsAnAddition;
    [Test] procedure AnEdgeOnlyInTheFirstIsARemoval;
    [Test] procedure TheSameEdgeMovedLineIsNotAChange;
    [Test] procedure TheSameEdgeInAnotherClauseIsAChange;
    [Test] procedure TheCountsDescribeBothGraphs;
    [Test] procedure ChangedUnitsAreListedInNameOrder;
  end;

implementation

uses
  System.SysUtils,
  Spring.Collections;

function EdgeBetween(const fromUnit : string; const toUnit : string) : TGraphEdge;
begin
  result := Default(TGraphEdge);
  result.FromUnit := fromUnit;
  result.ToUnit := toUnit;
  result.Section := usInterface;
  result.Certainty := ecUnconditional;
end;

/// <summary>Renders a list of names as "A,B,C" so a test can assert on the order too.</summary>
function Joined(const names : IReadOnlyList<string>) : string;
begin
  result := string.Join(',', names.ToArray);
end;

{ TDominatorTests }

procedure TDominatorTests.Setup;
begin
  FGraph := TUnitGraph.Create;
end;

procedure TDominatorTests.GivenEdge(const fromUnit : string; const toUnit : string);
begin
  FGraph.AddEdge(EdgeBetween(fromUnit, toUnit));
end;

function TDominatorTests.Tree : IDominatorTree;
begin
  result := TDominators.Build(FGraph, 'MyApp');
end;

procedure TDominatorTests.TheRootDominatesNothingAboveIt;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual('', Tree.ImmediateDominator('MyApp'));
end;

procedure TDominatorTests.AChainMakesEveryUnitDominateTheNext;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Inner');
  GivenEdge('Inner', 'Vcl.Graphics');

  Assert.AreEqual('Inner', Tree.ImmediateDominator('Vcl.Graphics'));
  Assert.AreEqual('Middle', Tree.ImmediateDominator('Inner'));
  Assert.AreEqual('MyApp', Tree.ImmediateDominator('Middle'));
end;

procedure TDominatorTests.AUnitReachedTwoWaysIsDominatedByWhereTheRoutesPart;
begin
  GivenEdge('MyApp', 'Left');
  GivenEdge('MyApp', 'Right');
  GivenEdge('Left', 'Shared');
  GivenEdge('Right', 'Shared');

  // neither Left nor Right is on every route, so cutting either changes nothing
  Assert.AreEqual('MyApp', Tree.ImmediateDominator('Shared'));
end;

procedure TDominatorTests.AUnitReachedOneWayIsDominatedByThatRoute;
begin
  GivenEdge('MyApp', 'Left');
  GivenEdge('MyApp', 'Right');
  GivenEdge('Left', 'Shared');

  Assert.AreEqual('Left', Tree.ImmediateDominator('Shared'));
end;

procedure TDominatorTests.ACycleDoesNotStopTheSearch;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitA');
  GivenEdge('UnitB', 'Vcl.Graphics');

  Assert.AreEqual('UnitB', Tree.ImmediateDominator('Vcl.Graphics'));
  Assert.AreEqual('UnitA', Tree.ImmediateDominator('UnitB'));
  Assert.AreEqual('MyApp', Tree.ImmediateDominator('UnitA'));
end;

procedure TDominatorTests.LookupIsCaseInsensitive;
begin
  GivenEdge('MyApp', 'Vcl.Graphics');
  Assert.AreEqual('MyApp', Tree.ImmediateDominator('VCL.GRAPHICS'));
  Assert.IsTrue(Tree.IsReachable('vcl.graphics'));
end;

procedure TDominatorTests.AnUnreachableUnitIsReportedAsSuch;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('Orphan', 'UnitB');

  Assert.IsTrue(Tree.IsReachable('UnitA'));
  Assert.IsFalse(Tree.IsReachable('UnitB'), 'nothing reaches UnitB from MyApp');
end;

procedure TDominatorTests.AnUnreachableUnitHasNoDominator;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('Orphan', 'UnitB');

  Assert.AreEqual('', Tree.ImmediateDominator('UnitB'));
end;

procedure TDominatorTests.AnUnknownRootGivesAnEmptyTree;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual<integer>(0, TDominators.Build(FGraph, 'NoSuchUnit').ReachableCount);
end;

procedure TDominatorTests.ReachableCountIncludesTheRoot;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Inner');

  Assert.AreEqual<integer>(3, Tree.ReachableCount);
end;

procedure TDominatorTests.ExclusiveReachOfALeafIsOne;
begin
  GivenEdge('MyApp', 'Vcl.Graphics');
  Assert.AreEqual<integer>(1, Tree.ExclusiveReach('Vcl.Graphics'));
end;

procedure TDominatorTests.ExclusiveReachCountsEverythingOnlyItReaches;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Inner');
  GivenEdge('Inner', 'Vcl.Graphics');

  // cutting Middle takes Inner and Vcl.Graphics with it
  Assert.AreEqual<integer>(3, Tree.ExclusiveReach('Middle'));
end;

procedure TDominatorTests.ExclusiveReachExcludesWhatIsReachableAnotherWay;
begin
  GivenEdge('MyApp', 'Left');
  GivenEdge('MyApp', 'Right');
  GivenEdge('Left', 'Shared');
  GivenEdge('Right', 'Shared');

  // Shared survives without Left, so Left only costs itself
  Assert.AreEqual<integer>(1, Tree.ExclusiveReach('Left'));
  Assert.AreEqual<integer>(1, Tree.ExclusiveReach('Shared'));
end;

procedure TDominatorTests.ExclusiveReachOfTheRootIsTheWholeGraph;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Inner');

  Assert.AreEqual<integer>(3, Tree.ExclusiveReach('MyApp'));
end;

procedure TDominatorTests.ExclusiveReachOfAnUnreachableUnitIsZero;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('Orphan', 'UnitB');

  Assert.AreEqual<integer>(0, Tree.ExclusiveReach('UnitB'));
end;

{ TCycleTests }

procedure TCycleTests.Setup;
begin
  FGraph := TUnitGraph.Create;
end;

procedure TCycleTests.GivenEdge(const fromUnit : string; const toUnit : string);
begin
  FGraph.AddEdge(EdgeBetween(fromUnit, toUnit));
end;

procedure TCycleTests.AGraphWithoutCyclesHasNone;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Inner');

  Assert.AreEqual<integer>(0, TCycles.Find(FGraph).Count);
end;

procedure TCycleTests.ADiamondIsNotACycle;
begin
  GivenEdge('MyApp', 'Left');
  GivenEdge('MyApp', 'Right');
  GivenEdge('Left', 'Shared');
  GivenEdge('Right', 'Shared');

  Assert.AreEqual<integer>(0, TCycles.Find(FGraph).Count,
    'two routes to the same unit is not the same as a loop');
end;

procedure TCycleTests.TwoUnitsUsingEachOtherAreAGroup;
var
  found : IReadOnlyList<TArray<string>>;
begin
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitA');

  found := TCycles.Find(FGraph);
  Assert.AreEqual<integer>(1, found.Count);
  Assert.AreEqual<integer>(2, Length(found[0]));
end;

procedure TCycleTests.AThreeUnitLoopIsOneGroup;
var
  found : IReadOnlyList<TArray<string>>;
begin
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitC');
  GivenEdge('UnitC', 'UnitA');

  found := TCycles.Find(FGraph);
  Assert.AreEqual<integer>(1, found.Count);
  Assert.AreEqual<integer>(3, Length(found[0]));
end;

procedure TCycleTests.TwoSeparateLoopsAreTwoGroups;
begin
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitA');
  GivenEdge('UnitC', 'UnitD');
  GivenEdge('UnitD', 'UnitC');

  Assert.AreEqual<integer>(2, TCycles.Find(FGraph).Count);
end;

procedure TCycleTests.TheLargestGroupComesFirst;
var
  found : IReadOnlyList<TArray<string>>;
begin
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitA');
  GivenEdge('UnitC', 'UnitD');
  GivenEdge('UnitD', 'UnitE');
  GivenEdge('UnitE', 'UnitC');

  found := TCycles.Find(FGraph);
  Assert.AreEqual<integer>(3, Length(found[0]), 'the worst tangle is the one to look at');
  Assert.AreEqual<integer>(2, Length(found[1]));
end;

procedure TCycleTests.AUnitOutsideTheLoopIsNotInTheGroup;
var
  found : IReadOnlyList<TArray<string>>;
  name : string;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitA');
  GivenEdge('UnitB', 'Vcl.Graphics');

  found := TCycles.Find(FGraph);
  Assert.AreEqual<integer>(1, found.Count);
  Assert.AreEqual<integer>(2, Length(found[0]));
  for name in found[0] do
    Assert.IsTrue(SameText(name, 'UnitA') or SameText(name, 'UnitB'), name);
end;

procedure TCycleTests.TheRoundTripShowsHowTheLoopCloses;
var
  found : IReadOnlyList<TArray<string>>;
  trip : TArray<string>;
begin
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitC');
  GivenEdge('UnitC', 'UnitA');

  found := TCycles.Find(FGraph);
  trip := TCycles.RoundTripIn(FGraph, found[0]);

  Assert.AreEqual<integer>(4, Length(trip), 'three units and back to the first');
  Assert.AreEqual(trip[0], trip[High(trip)], 'a round trip ends where it started');
end;

procedure TCycleTests.TheRoundTripIsTheShortestOne;
var
  trip : TArray<string>;
begin
  // UnitA gets back to itself the long way round or straight through UnitD
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitC');
  GivenEdge('UnitC', 'UnitA');
  GivenEdge('UnitA', 'UnitD');
  GivenEdge('UnitD', 'UnitA');

  trip := TCycles.RoundTripIn(FGraph, TArray<string>.Create('UnitA', 'UnitB', 'UnitC', 'UnitD'));
  Assert.AreEqual('UnitA>UnitD>UnitA', string.Join('>', trip));
end;

procedure TCycleTests.TheRoundTripOfAGroupOfOneIsEmpty;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual<integer>(0,
    Length(TCycles.RoundTripIn(FGraph, TArray<string>.Create('UnitA'))));
end;

{ TReachTests }

procedure TReachTests.Setup;
begin
  FGraph := TUnitGraph.Create;
end;

procedure TReachTests.GivenEdge(const fromUnit : string; const toUnit : string);
begin
  FGraph.AddEdge(EdgeBetween(fromUnit, toUnit));
end;

procedure TReachTests.CountFromIncludesTheStart;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual<integer>(2, TReach.CountFrom(FGraph, 'MyApp'));
end;

procedure TReachTests.CountFromFollowsTheWholeChain;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Inner');
  GivenEdge('Inner', 'Vcl.Graphics');

  Assert.AreEqual<integer>(4, TReach.CountFrom(FGraph, 'MyApp'));
  Assert.AreEqual<integer>(2, TReach.CountFrom(FGraph, 'Inner'));
end;

procedure TReachTests.CountFromIsZeroForAnUnknownUnit;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual<integer>(0, TReach.CountFrom(FGraph, 'NoSuchUnit'));
end;

procedure TReachTests.RemovingAnEdgeDropsWhatOnlyItReached;
begin
  GivenEdge('MyApp', 'Middle');
  GivenEdge('Middle', 'Inner');
  GivenEdge('MyApp', 'Other');

  // without MyApp uses Middle, both Middle and Inner go
  Assert.AreEqual<integer>(2, TReach.CountWithoutEdge(FGraph, 'MyApp', 'MyApp', 'Middle'));
end;

procedure TReachTests.RemovingAnEdgeDropsNothingWhenThereIsAnotherRoute;
begin
  GivenEdge('MyApp', 'Shared');
  GivenEdge('MyApp', 'Other');
  GivenEdge('Other', 'Shared');

  // deleting the direct uses changes nothing, Other still brings it in
  Assert.AreEqual<integer>(3, TReach.CountWithoutEdge(FGraph, 'MyApp', 'MyApp', 'Shared'));
end;

procedure TReachTests.RemovingAnEdgeThatIsNotThereChangesNothing;
begin
  GivenEdge('MyApp', 'UnitA');
  Assert.AreEqual<integer>(2,
    TReach.CountWithoutEdge(FGraph, 'MyApp', 'NoSuchUnit', 'AlsoMissing'));
end;

procedure TReachTests.ACycleDoesNotHangTheCount;
begin
  GivenEdge('MyApp', 'UnitA');
  GivenEdge('UnitA', 'UnitB');
  GivenEdge('UnitB', 'UnitA');

  Assert.AreEqual<integer>(3, TReach.CountFrom(FGraph, 'MyApp'));
end;

{ TGraphDiffTests }

procedure TGraphDiffTests.Setup;
begin
  FBefore := TUnitGraph.Create;
  FAfter := TUnitGraph.Create;
end;

procedure TGraphDiffTests.GivenEdge(const graph : IUnitGraph; const fromUnit : string;
  const toUnit : string);
begin
  graph.AddEdge(EdgeBetween(fromUnit, toUnit));
end;

procedure TGraphDiffTests.TwoIdenticalGraphsDifferInNothing;
var
  delta : TGraphDelta;
begin
  GivenEdge(FBefore, 'MyApp', 'UnitA');
  GivenEdge(FAfter, 'MyApp', 'UnitA');

  delta := TGraphDiff.Compare(FBefore, FAfter);
  Assert.IsTrue(delta.IsEmpty);
  Assert.AreEqual<integer>(0, delta.UnitChange);
  Assert.AreEqual<integer>(0, delta.EdgeChange);
end;

procedure TGraphDiffTests.AUnitOnlyInTheSecondIsAnAddition;
var
  delta : TGraphDelta;
begin
  GivenEdge(FBefore, 'MyApp', 'UnitA');
  GivenEdge(FAfter, 'MyApp', 'UnitA');
  GivenEdge(FAfter, 'MyApp', 'UnitB');

  delta := TGraphDiff.Compare(FBefore, FAfter);
  Assert.AreEqual<integer>(1, Length(delta.AddedUnits));
  Assert.AreEqual('UnitB', delta.AddedUnits[0]);
  Assert.AreEqual<integer>(0, Length(delta.RemovedUnits));
end;

procedure TGraphDiffTests.AUnitOnlyInTheFirstIsARemoval;
var
  delta : TGraphDelta;
begin
  GivenEdge(FBefore, 'MyApp', 'Vcl.Forms');
  GivenEdge(FAfter, 'MyApp', 'UnitA');
  GivenEdge(FBefore, 'MyApp', 'UnitA');

  delta := TGraphDiff.Compare(FBefore, FAfter);
  Assert.AreEqual<integer>(1, Length(delta.RemovedUnits));
  Assert.AreEqual('Vcl.Forms', delta.RemovedUnits[0]);
end;

procedure TGraphDiffTests.AnEdgeOnlyInTheSecondIsAnAddition;
var
  delta : TGraphDelta;
begin
  GivenEdge(FBefore, 'MyApp', 'UnitA');
  GivenEdge(FBefore, 'MyApp', 'UnitB');
  GivenEdge(FAfter, 'MyApp', 'UnitA');
  GivenEdge(FAfter, 'MyApp', 'UnitB');
  GivenEdge(FAfter, 'UnitA', 'UnitB');

  delta := TGraphDiff.Compare(FBefore, FAfter);
  Assert.AreEqual<integer>(1, Length(delta.AddedEdges));
  Assert.AreEqual('UnitA', delta.AddedEdges[0].FromUnit);
  Assert.AreEqual('UnitB', delta.AddedEdges[0].ToUnit);
end;

procedure TGraphDiffTests.AnEdgeOnlyInTheFirstIsARemoval;
var
  delta : TGraphDelta;
begin
  GivenEdge(FBefore, 'MyApp', 'UnitA');
  GivenEdge(FBefore, 'UnitA', 'Vcl.Forms');
  GivenEdge(FAfter, 'MyApp', 'UnitA');
  GivenEdge(FAfter, 'MyApp', 'Vcl.Forms');

  delta := TGraphDiff.Compare(FBefore, FAfter);
  Assert.AreEqual<integer>(1, Length(delta.RemovedEdges));
  Assert.AreEqual('UnitA', delta.RemovedEdges[0].FromUnit);
  Assert.AreEqual('Vcl.Forms', delta.RemovedEdges[0].ToUnit);
end;

procedure TGraphDiffTests.TheSameEdgeMovedLineIsNotAChange;
var
  edge : TGraphEdge;
  delta : TGraphDelta;
begin
  edge := EdgeBetween('MyApp', 'UnitA');
  edge.FileName := 'MyApp.dpr';
  edge.Line := 10;
  FBefore.AddEdge(edge);

  edge.Line := 40;
  FAfter.AddEdge(edge);

  delta := TGraphDiff.Compare(FBefore, FAfter);
  Assert.IsTrue(delta.IsEmpty, 'a uses entry that only moved down the file is the same fact');
end;

procedure TGraphDiffTests.TheSameEdgeInAnotherClauseIsAChange;
var
  edge : TGraphEdge;
  delta : TGraphDelta;
begin
  GivenEdge(FBefore, 'MyApp', 'UnitA');

  edge := EdgeBetween('MyApp', 'UnitA');
  edge.Section := usImplementation;
  FAfter.AddEdge(edge);

  delta := TGraphDiff.Compare(FBefore, FAfter);
  Assert.AreEqual<integer>(1, Length(delta.RemovedEdges), 'gone from the interface');
  Assert.AreEqual<integer>(1, Length(delta.AddedEdges), 'and now in the implementation');
end;

procedure TGraphDiffTests.TheCountsDescribeBothGraphs;
var
  delta : TGraphDelta;
begin
  GivenEdge(FBefore, 'MyApp', 'UnitA');
  GivenEdge(FBefore, 'MyApp', 'UnitB');
  GivenEdge(FAfter, 'MyApp', 'UnitA');

  delta := TGraphDiff.Compare(FBefore, FAfter);
  Assert.AreEqual<integer>(3, delta.BeforeUnits);
  Assert.AreEqual<integer>(2, delta.AfterUnits);
  Assert.AreEqual<integer>(2, delta.BeforeEdges);
  Assert.AreEqual<integer>(1, delta.AfterEdges);
  Assert.AreEqual<integer>(-1, delta.UnitChange);
  Assert.AreEqual<integer>(-1, delta.EdgeChange);
end;

procedure TGraphDiffTests.ChangedUnitsAreListedInNameOrder;
var
  delta : TGraphDelta;
begin
  GivenEdge(FBefore, 'MyApp', 'Zebra');
  GivenEdge(FBefore, 'MyApp', 'Apple');
  GivenEdge(FBefore, 'MyApp', 'Mango');
  GivenEdge(FAfter, 'MyApp', 'Kept');

  delta := TGraphDiff.Compare(FBefore, FAfter);
  Assert.AreEqual('Apple,Mango,Zebra', string.Join(',', delta.RemovedUnits));
end;

initialization
  TDUnitX.RegisterTestFixture(TDominatorTests);
  TDUnitX.RegisterTestFixture(TCycleTests);
  TDUnitX.RegisterTestFixture(TReachTests);
  TDUnitX.RegisterTestFixture(TGraphDiffTests);

end.
