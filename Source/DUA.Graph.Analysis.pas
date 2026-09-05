unit DUA.Graph.Analysis;

{
  Graph algorithms that answer "what would I have to change", kept out of DUA.Graph so
  that unit stays about holding the graph. Everything here works through IUnitGraph's
  public surface, and keys every lookup the same way DUA.Graph does - by uppercasing the
  name. Spring has a case insensitive comparer, but mixing the two idioms in one codebase
  would make two identical looking dictionaries behave differently.
}

interface

uses
  Spring.Collections,
  DUA.Types,
  DUA.Graph;

type
  /// <summary>
  ///   Which units every route from the root has to pass through. Built once for a root
  ///   and then answers about any unit, which is what makes ranking a whole project by
  ///   what each unit exclusively brings in cheap on a large graph.
  /// </summary>
  IDominatorTree = interface
    ['{2C7A94E1-5D8B-4F03-9A61-7E4028B5C3D9}']
    /// <summary>Whether the root reaches this unit at all.</summary>
    function IsReachable(const unitName : string) : boolean;
    /// <summary>
    ///   The nearest unit that every route to this one passes through. Empty for the root
    ///   itself and for anything unreachable.
    /// </summary>
    function ImmediateDominator(const unitName : string) : string;
    /// <summary>
    ///   How many units become unreachable from the root if this one goes, itself
    ///   included. Zero when the unit is not reachable in the first place.
    /// </summary>
    function ExclusiveReach(const unitName : string) : integer;
    /// <summary>Units the root reaches, itself included.</summary>
    function ReachableCount : integer;
  end;

  TDominators = record
  public
    class function Build(const graph : IUnitGraph; const root : string) : IDominatorTree; static;
  end;

  TCycles = record
  public
    /// <summary>
    ///   Every group of units that all reach each other, largest first. Groups of one are
    ///   left out - a unit is trivially its own group and says nothing.
    /// </summary>
    class function Find(const graph : IUnitGraph) : IReadOnlyList<TArray<string>>; static;
    /// <summary>
    ///   A shortest round trip through the first unit of a group, first unit repeated at
    ///   the end, so the cycle can be shown rather than just named.
    /// </summary>
    class function RoundTripIn(const graph : IUnitGraph;
                               const component : TArray<string>) : TArray<string>; static;
  end;

  TReach = record
  public
    /// <summary>Units reachable from a starting unit, itself included.</summary>
    class function CountFrom(const graph : IUnitGraph; const root : string) : integer; static;
    /// <summary>
    ///   The same count with one dependency pretended away, which is what answers "how
    ///   much would deleting this uses entry actually save".
    /// </summary>
    class function CountWithoutEdge(const graph : IUnitGraph; const root : string;
                                    const fromUnit : string;
                                    const toUnit : string) : integer; static;
  end;

  /// <summary>What changed between two graphs. Counts are of the whole graph.</summary>
  TGraphDelta = record
    AddedUnits : TArray<string>;
    RemovedUnits : TArray<string>;
    AddedEdges : TArray<TGraphEdge>;
    RemovedEdges : TArray<TGraphEdge>;
    BeforeUnits : integer;
    AfterUnits : integer;
    BeforeEdges : integer;
    AfterEdges : integer;
    function UnitChange : integer;
    function EdgeChange : integer;
    function IsEmpty : boolean;
  end;

  TGraphDiff = record
  public
    class function Compare(const before : IUnitGraph;
                           const after : IUnitGraph) : TGraphDelta; static;
  end;

implementation

uses
  System.SysUtils;

/// <summary>
///   The same key DUA.Graph uses. Every dictionary and set in this unit goes through it.
/// </summary>
function Key(const value : string) : string;
begin
  result := UpperCase(value);
end;

type
  /// <summary>
  ///   A depth first walk has to visit a unit twice - once to push its children and once
  ///   when they are all done - and doing that with an explicit stack rather than
  ///   recursion is what keeps a three thousand unit chain off the call stack.
  /// </summary>
  TWalkStep = record
    Name : string;
    Expanded : boolean;
    constructor Create(const unitName : string; const isExpanded : boolean);
  end;

constructor TWalkStep.Create(const unitName : string; const isExpanded : boolean);
begin
  Name := unitName;
  Expanded := isExpanded;
end;

/// <summary>
///   Units reachable from a start, in the order a depth first walk finishes with them -
///   deepest first. Reversing it gives an order in which every unit comes after something
///   that reaches it, which is what the dominator iteration needs.
/// </summary>
function PostOrderFrom(const graph : IUnitGraph; const root : string) : IList<string>;
var
  stack : IStack<TWalkStep>;
  visited : ISet<string>;
  step : TWalkStep;
  child : string;
begin
  result := TCollections.CreateList<string>;
  stack := TCollections.CreateStack<TWalkStep>;
  visited := TCollections.CreateSet<string>;

  stack.Push(TWalkStep.Create(root, false));
  while stack.Count > 0 do
  begin
    step := stack.Pop;

    if step.Expanded then
    begin
      result.Add(step.Name);
      Continue;
    end;

    if visited.Contains(Key(step.Name)) then
      Continue;
    visited.Add(Key(step.Name));

    // back on the stack so it is collected once everything below it is
    stack.Push(TWalkStep.Create(step.Name, true));
    for child in graph.Dependencies(step.Name) do
      if not visited.Contains(Key(child)) then
        stack.Push(TWalkStep.Create(child, false));
  end;
end;

{ TDominatorTree }

type
  TDominatorTree = class(TInterfacedObject, IDominatorTree)
  private
    /// <summary>Reverse post order - the root first, then every unit after a dominator.</summary>
    FOrder : IList<string>;
    FIndexOf : IDictionary<string, integer>;
    /// <summary>Immediate dominator of each unit, as an index into FOrder.</summary>
    FIdom : TArray<integer>;
    /// <summary>How many units sit at or below each one in the dominator tree.</summary>
    FSubtree : TArray<integer>;
    function Intersect(const left : integer; const right : integer) : integer;
    procedure Solve(const graph : IUnitGraph);
    procedure MeasureSubtrees;
  protected
    function IsReachable(const unitName : string) : boolean;
    function ImmediateDominator(const unitName : string) : string;
    function ExclusiveReach(const unitName : string) : integer;
    function ReachableCount : integer;
  public
    constructor Create(const graph : IUnitGraph; const rootUnit : string);
  end;

constructor TDominatorTree.Create(const graph : IUnitGraph; const rootUnit : string);
var
  postOrder : IList<string>;
  index : integer;
begin
  inherited Create;
  FOrder := TCollections.CreateList<string>;
  FIndexOf := TCollections.CreateDictionary<string, integer>;

  if not graph.ContainsNode(rootUnit) then
    Exit;

  postOrder := PostOrderFrom(graph, rootUnit);
  for index := postOrder.Count - 1 downto 0 do
  begin
    FIndexOf[Key(postOrder[index])] := FOrder.Count;
    FOrder.Add(postOrder[index]);
  end;

  Solve(graph);
  MeasureSubtrees;
end;

/// <summary>
///   The nearest unit that dominates both, found by walking each up its own dominator
///   chain until they meet. Reverse post order numbering is what makes "further from the
///   root" the same as "a larger index", so the walk always terminates at the root.
/// </summary>
function TDominatorTree.Intersect(const left : integer; const right : integer) : integer;
var
  finger1 : integer;
  finger2 : integer;
begin
  finger1 := left;
  finger2 := right;
  while finger1 <> finger2 do
  begin
    while finger1 > finger2 do
      finger1 := FIdom[finger1];
    while finger2 > finger1 do
      finger2 := FIdom[finger2];
  end;
  result := finger1;
end;

procedure TDominatorTree.Solve(const graph : IUnitGraph);
var
  index : integer;
  predecessorIndex : integer;
  candidate : integer;
  predecessor : string;
  changed : boolean;
begin
  SetLength(FIdom, FOrder.Count);
  for index := 0 to High(FIdom) do
    FIdom[index] := -1;
  if FOrder.Count = 0 then
    Exit;
  // the root dominates itself, which is what gives the iteration something to start from
  FIdom[0] := 0;

  // Cooper, Harvey and Kennedy: keep folding every unit's predecessors together until
  // nothing moves. On a dependency graph this settles in two or three passes.
  repeat
    changed := false;
    for index := 1 to FOrder.Count - 1 do
    begin
      candidate := -1;
      for predecessor in graph.Dependents(FOrder[index]) do
      begin
        // a unit the root cannot reach says nothing about what dominates this one
        if not FIndexOf.TryGetValue(Key(predecessor), predecessorIndex) then
          Continue;
        if FIdom[predecessorIndex] = -1 then
          Continue;

        if candidate = -1 then
          candidate := predecessorIndex
        else
          candidate := Intersect(predecessorIndex, candidate);
      end;

      if (candidate <> -1) and (FIdom[index] <> candidate) then
      begin
        FIdom[index] := candidate;
        changed := true;
      end;
    end;
  until not changed;
end;

procedure TDominatorTree.MeasureSubtrees;
var
  index : integer;
begin
  SetLength(FSubtree, FOrder.Count);
  for index := 0 to High(FSubtree) do
    FSubtree[index] := 1;

  // A dominator always sits earlier in reverse post order than what it dominates, so
  // working backwards adds each unit into its dominator before that one is itself added.
  for index := FOrder.Count - 1 downto 1 do
    if FIdom[index] >= 0 then
      Inc(FSubtree[FIdom[index]], FSubtree[index]);
end;

function TDominatorTree.IsReachable(const unitName : string) : boolean;
begin
  result := FIndexOf.ContainsKey(Key(unitName));
end;

function TDominatorTree.ImmediateDominator(const unitName : string) : string;
var
  index : integer;
begin
  result := '';
  if not FIndexOf.TryGetValue(Key(unitName), index) then
    Exit;
  if index = 0 then
    Exit;
  if FIdom[index] < 0 then
    Exit;
  result := FOrder[FIdom[index]];
end;

function TDominatorTree.ExclusiveReach(const unitName : string) : integer;
var
  index : integer;
begin
  if FIndexOf.TryGetValue(Key(unitName), index) then
    result := FSubtree[index]
  else
    result := 0;
end;

function TDominatorTree.ReachableCount : integer;
begin
  result := FOrder.Count;
end;

{ TDominators }

class function TDominators.Build(const graph : IUnitGraph;
  const root : string) : IDominatorTree;
begin
  result := TDominatorTree.Create(graph, root);
end;

{ TCycles }

class function TCycles.Find(const graph : IUnitGraph) : IReadOnlyList<TArray<string>>;
var
  components : IList<TArray<string>>;
  finished : IList<string>;
  visited : ISet<string>;
  assigned : ISet<string>;
  stack : IStack<TWalkStep>;
  plain : IStack<string>;
  node : TGraphNode;
  step : TWalkStep;
  current : string;
  child : string;
  previous : string;
  component : IList<string>;
  index : integer;
begin
  components := TCollections.CreateList<TArray<string>>;
  result := components.AsReadOnly;

  // Kosaraju: finish every unit in the forward direction, then take them in reverse
  // order and see how far each gets going backwards. Whatever is reachable both ways is
  // a group that references itself.
  finished := TCollections.CreateList<string>;
  visited := TCollections.CreateSet<string>;
  stack := TCollections.CreateStack<TWalkStep>;

  for node in graph.Nodes do
  begin
    if visited.Contains(Key(node.Name)) then
      Continue;

    stack.Push(TWalkStep.Create(node.Name, false));
    while stack.Count > 0 do
    begin
      step := stack.Pop;

      if step.Expanded then
      begin
        finished.Add(step.Name);
        Continue;
      end;

      if visited.Contains(Key(step.Name)) then
        Continue;
      visited.Add(Key(step.Name));

      stack.Push(TWalkStep.Create(step.Name, true));
      for child in graph.Dependencies(step.Name) do
        if not visited.Contains(Key(child)) then
          stack.Push(TWalkStep.Create(child, false));
    end;
  end;

  assigned := TCollections.CreateSet<string>;
  plain := TCollections.CreateStack<string>;

  for index := finished.Count - 1 downto 0 do
  begin
    if assigned.Contains(Key(finished[index])) then
      Continue;

    component := TCollections.CreateList<string>;
    plain.Push(finished[index]);
    while plain.Count > 0 do
    begin
      current := plain.Pop;
      if assigned.Contains(Key(current)) then
        Continue;
      assigned.Add(Key(current));
      component.Add(current);

      for previous in graph.Dependents(current) do
        if not assigned.Contains(Key(previous)) then
          plain.Push(previous);
    end;

    // one unit on its own is not a circular reference, it is just a unit
    if component.Count > 1 then
      components.Add(component.ToArray);
  end;

  components.Sort(
    function(const left, right : TArray<string>) : integer
    begin
      result := Length(right) - Length(left);
      if result = 0 then
        result := CompareText(left[0], right[0]);
    end);
end;

class function TCycles.RoundTripIn(const graph : IUnitGraph;
  const component : TArray<string>) : TArray<string>;
var
  members : ISet<string>;
  predecessors : IDictionary<string, string>;
  visited : ISet<string>;
  queue : IQueue<string>;
  chain : IList<string>;
  start : string;
  current : string;
  next : string;
  step : string;
  index : integer;
begin
  result := nil;
  if Length(component) < 2 then
    Exit;

  members := TCollections.CreateSet<string>;
  for step in component do
    members.Add(Key(step));

  start := component[0];
  predecessors := TCollections.CreateDictionary<string, string>;
  visited := TCollections.CreateSet<string>;
  queue := TCollections.CreateQueue<string>;

  visited.Add(Key(start));
  queue.Enqueue(start);

  while queue.Count > 0 do
  begin
    current := queue.Dequeue;
    for next in graph.Dependencies(current) do
    begin
      // routes out of the group cannot come back into it, or it would be one group
      if not members.Contains(Key(next)) then
        Continue;

      if SameText(next, start) then
      begin
        chain := TCollections.CreateList<string>;
        step := current;
        while not SameText(step, start) do
        begin
          chain.Add(step);
          step := predecessors[Key(step)];
        end;
        chain.Add(start);

        // built backwards from the unit that closes the loop, so turn it round and
        // repeat the start at the end to show it really is a round trip
        SetLength(result, chain.Count + 1);
        for index := 0 to chain.Count - 1 do
          result[index] := chain[chain.Count - 1 - index];
        result[chain.Count] := start;
        Exit;
      end;

      if not visited.Contains(Key(next)) then
      begin
        visited.Add(Key(next));
        predecessors[Key(next)] := current;
        queue.Enqueue(next);
      end;
    end;
  end;
end;

{ TReach }

/// <summary>
///   Breadth first from a start, optionally refusing one dependency. Its own search
///   rather than the graph's cached one, because the graph has no way to cache an answer
///   about a dependency that is not really there.
/// </summary>
function CountReachable(const graph : IUnitGraph; const root : string;
  const skipFrom : string; const skipTo : string) : integer;
var
  visited : ISet<string>;
  queue : IQueue<string>;
  current : string;
  neighbour : string;
begin
  result := 0;
  if not graph.ContainsNode(root) then
    Exit;

  visited := TCollections.CreateSet<string>;
  queue := TCollections.CreateQueue<string>;
  visited.Add(Key(root));
  queue.Enqueue(root);

  while queue.Count > 0 do
  begin
    current := queue.Dequeue;
    for neighbour in graph.Dependencies(current) do
    begin
      if (skipFrom <> '') and SameText(current, skipFrom) and SameText(neighbour, skipTo) then
        Continue;
      if visited.Contains(Key(neighbour)) then
        Continue;
      visited.Add(Key(neighbour));
      queue.Enqueue(neighbour);
    end;
  end;

  result := visited.Count;
end;

class function TReach.CountFrom(const graph : IUnitGraph; const root : string) : integer;
begin
  result := CountReachable(graph, root, '', '');
end;

class function TReach.CountWithoutEdge(const graph : IUnitGraph; const root : string;
  const fromUnit : string; const toUnit : string) : integer;
begin
  result := CountReachable(graph, root, fromUnit, toUnit);
end;

{ TGraphDelta }

function TGraphDelta.UnitChange : integer;
begin
  result := AfterUnits - BeforeUnits;
end;

function TGraphDelta.EdgeChange : integer;
begin
  result := AfterEdges - BeforeEdges;
end;

function TGraphDelta.IsEmpty : boolean;
begin
  result := (Length(AddedUnits) = 0) and (Length(RemovedUnits) = 0) and
            (Length(AddedEdges) = 0) and (Length(RemovedEdges) = 0);
end;

{ TGraphDiff }

/// <summary>
///   The same idea of sameness AddEdge uses, so a dependency that only moved line is not
///   reported as having changed.
/// </summary>
function EdgeKey(const edge : TGraphEdge) : string;
begin
  result := Format('%s|%s|%d|%d|%s', [Key(edge.FromUnit), Key(edge.ToUnit),
    Ord(edge.Section), Ord(edge.Certainty), Key(edge.Condition)]);
end;

function EdgeKeysOf(const graph : IUnitGraph) : ISet<string>;
var
  edge : TGraphEdge;
begin
  result := TCollections.CreateSet<string>;
  for edge in graph.Edges do
    result.Add(EdgeKey(edge));
end;

function NamesMissingFrom(const graph : IUnitGraph; const other : IUnitGraph) : TArray<string>;
var
  missing : IList<string>;
  node : TGraphNode;
begin
  missing := TCollections.CreateList<string>;
  for node in graph.Nodes do
    if not other.ContainsNode(node.Name) then
      missing.Add(node.Name);

  missing.Sort(
    function(const left, right : string) : integer
    begin
      result := CompareText(left, right);
    end);
  result := missing.ToArray;
end;

function EdgesMissingFrom(const graph : IUnitGraph; const otherKeys : ISet<string>) : TArray<TGraphEdge>;
var
  missing : IList<TGraphEdge>;
  edge : TGraphEdge;
begin
  missing := TCollections.CreateList<TGraphEdge>;
  for edge in graph.Edges do
    if not otherKeys.Contains(EdgeKey(edge)) then
      missing.Add(edge);

  missing.Sort(
    function(const left, right : TGraphEdge) : integer
    begin
      result := CompareText(left.FromUnit, right.FromUnit);
      if result = 0 then
        result := CompareText(left.ToUnit, right.ToUnit);
      if result = 0 then
        result := Ord(left.Section) - Ord(right.Section);
    end);
  result := missing.ToArray;
end;

class function TGraphDiff.Compare(const before : IUnitGraph;
  const after : IUnitGraph) : TGraphDelta;
var
  beforeKeys : ISet<string>;
  afterKeys : ISet<string>;
begin
  result := Default(TGraphDelta);
  result.BeforeUnits := before.Nodes.Count;
  result.AfterUnits := after.Nodes.Count;
  result.BeforeEdges := before.Edges.Count;
  result.AfterEdges := after.Edges.Count;

  result.RemovedUnits := NamesMissingFrom(before, after);
  result.AddedUnits := NamesMissingFrom(after, before);

  beforeKeys := EdgeKeysOf(before);
  afterKeys := EdgeKeysOf(after);
  result.RemovedEdges := EdgesMissingFrom(before, afterKeys);
  result.AddedEdges := EdgesMissingFrom(after, beforeKeys);
end;

end.
