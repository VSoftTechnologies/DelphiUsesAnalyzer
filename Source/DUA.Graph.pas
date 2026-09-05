unit DUA.Graph;

interface

uses
  Spring.Collections,
  DUA.Types;

type
  TGraphNode = class
  public
    /// <summary>The canonical name, as the compiler would resolve it.</summary>
    Name : string;
    FileName : string;
    Kind : TUnitKind;
    /// <summary>False when we never read the source, so its own uses are unknown.</summary>
    Parsed : boolean;
    /// <summary>Other spellings seen in uses clauses, eg Classes for System.Classes.</summary>
    Aliases : IList<string>;
    constructor Create(const unitName : string);
  end;

  TGraphEdge = record
    FromUnit : string;
    ToUnit : string;
    Section : TUsesSection;
    Certainty : TEdgeCertainty;
    Condition : string;
    FileName : string;
    Line : integer;
  end;

  IUnitGraph = interface
    ['{8B3F2A47-1E6D-4C90-B5A8-0F7C42E9D316}']
    /// <summary>Find or create the node for a name. Names are case insensitive.</summary>
    function EnsureNode(const name : string) : TGraphNode;
    function TryFindNode(const name : string; out node : TGraphNode) : boolean;
    function ContainsNode(const name : string) : boolean;
    /// <summary>
    ///   Every node matching a name or a glob, sorted. An alias counts as a match too,
    ///   so asking about Forms finds the Vcl.Forms the compiler resolved it to.
    /// </summary>
    function FindNodes(const pattern : string) : IReadOnlyList<TGraphNode>;
    procedure AddEdge(const edge : TGraphEdge);

    function GetNodes : IReadOnlyList<TGraphNode>;
    function GetEdges : IReadOnlyList<TGraphEdge>;
    /// <summary>Names of the units this one uses.</summary>
    function Dependencies(const unitName : string) : IReadOnlyList<string>;
    /// <summary>Names of the units that use this one - the reverse index.</summary>
    function Dependents(const unitName : string) : IReadOnlyList<string>;
    /// <summary>
    ///   Every edge arriving at this unit, so a caller can say not just who references
    ///   it but from which clause and which line.
    /// </summary>
    function EdgesTo(const unitName : string) : IReadOnlyList<TGraphEdge>;
    /// <summary>
    ///   Every edge leaving this unit. Dependencies says which units it reaches, this
    ///   says where each was written, which is what makes a uses entry findable.
    /// </summary>
    function EdgesFrom(const unitName : string) : IReadOnlyList<TGraphEdge>;

    /// <summary>
    ///   Shortest dependency chains from one unit to another, each starting at fromUnit
    ///   and ending at toUnit. Empty when there is no route. Cycles are handled.
    /// </summary>
    function FindPaths(const fromUnit : string; const toUnit : string;
                       const maxPaths : integer) : IReadOnlyList<TArray<string>>;
    /// <summary>
    ///   Every unit reachable from this one, itself included, nearest first. Shares the
    ///   search the chain finding already does, so asking is close to free.
    /// </summary>
    function ReachableFrom(const fromUnit : string) : IReadOnlyList<string>;

    property Nodes : IReadOnlyList<TGraphNode> read GetNodes;
    property Edges : IReadOnlyList<TGraphEdge> read GetEdges;
  end;

  TUnitGraph = class(TInterfacedObject, IUnitGraph)
  private
    FNodes : IList<TGraphNode>;
    FNodesByName : IDictionary<string, TGraphNode>;
    FEdges : IList<TGraphEdge>;
    FEdgeKeys : ISet<string>;
    FForward : IDictionary<string, IList<string>>;
    FReverse : IDictionary<string, IList<string>>;
    FEdgesByTarget : IDictionary<string, IList<TGraphEdge>>;
    FEdgesBySource : IDictionary<string, IList<TGraphEdge>>;
    /// <summary>
    ///   The breadth first search from one starting unit. It does not depend on the
    ///   target at all, so answering about a hundred units reuses one search rather
    ///   than running a hundred.
    /// </summary>
    FSearchFrom : string;
    FSearchDepth : IDictionary<string, integer>;
    FSearchPredecessors : IDictionary<string, IList<string>>;
    procedure EnsureSearchFrom(const fromUnit : string);
    function AdjacentTo(const map : IDictionary<string, IList<string>>;
                        const unitName : string) : IReadOnlyList<string>;
    procedure Link(const map : IDictionary<string, IList<string>>;
                   const fromName : string; const toName : string);
    function EdgesIn(const map : IDictionary<string, IList<TGraphEdge>>;
                     const unitName : string) : IReadOnlyList<TGraphEdge>;
    procedure Attach(const map : IDictionary<string, IList<TGraphEdge>>;
                     const unitName : string; const edge : TGraphEdge);
  protected
    function EnsureNode(const name : string) : TGraphNode;
    function TryFindNode(const name : string; out node : TGraphNode) : boolean;
    function ContainsNode(const name : string) : boolean;
    function FindNodes(const pattern : string) : IReadOnlyList<TGraphNode>;
    procedure AddEdge(const edge : TGraphEdge);
    function GetNodes : IReadOnlyList<TGraphNode>;
    function GetEdges : IReadOnlyList<TGraphEdge>;
    function Dependencies(const unitName : string) : IReadOnlyList<string>;
    function Dependents(const unitName : string) : IReadOnlyList<string>;
    function EdgesTo(const unitName : string) : IReadOnlyList<TGraphEdge>;
    function EdgesFrom(const unitName : string) : IReadOnlyList<TGraphEdge>;
    function FindPaths(const fromUnit : string; const toUnit : string;
                       const maxPaths : integer) : IReadOnlyList<TArray<string>>;
    function ReachableFrom(const fromUnit : string) : IReadOnlyList<string>;
  public
    constructor Create;
  end;

implementation

uses
  System.SysUtils;

constructor TGraphNode.Create(const unitName : string);
begin
  inherited Create;
  Name := unitName;
  Kind := ukUnresolved;
  Aliases := TCollections.CreateList<string>;
end;

function Key(const value : string) : string;
begin
  result := UpperCase(value);
end;

{ TUnitGraph }

constructor TUnitGraph.Create;
begin
  inherited Create;
  FNodes := TCollections.CreateObjectList<TGraphNode>(true);
  FNodesByName := TCollections.CreateDictionary<string, TGraphNode>;
  FEdges := TCollections.CreateList<TGraphEdge>;
  FEdgeKeys := TCollections.CreateSet<string>;
  FForward := TCollections.CreateDictionary<string, IList<string>>;
  FReverse := TCollections.CreateDictionary<string, IList<string>>;
  FEdgesByTarget := TCollections.CreateDictionary<string, IList<TGraphEdge>>;
  FEdgesBySource := TCollections.CreateDictionary<string, IList<TGraphEdge>>;
end;

function TUnitGraph.EnsureNode(const name : string) : TGraphNode;
begin
  if FNodesByName.TryGetValue(Key(name), result) then
    Exit;

  result := TGraphNode.Create(name);
  FNodes.Add(result);
  FNodesByName[Key(name)] := result;
end;

function TUnitGraph.TryFindNode(const name : string; out node : TGraphNode) : boolean;
begin
  result := FNodesByName.TryGetValue(Key(name), node);
  if not result then
    node := nil;
end;

function TUnitGraph.ContainsNode(const name : string) : boolean;
begin
  result := FNodesByName.ContainsKey(Key(name));
end;

function TUnitGraph.FindNodes(const pattern : string) : IReadOnlyList<TGraphNode>;
var
  matches : IList<TGraphNode>;
  node : TGraphNode;
  alias : string;
  matched : boolean;
begin
  matches := TCollections.CreateList<TGraphNode>;
  result := matches.AsReadOnly;
  if Trim(pattern) = '' then
    Exit;

  // an exact name is by far the common case and needs no scan
  if not IsWildcardPattern(pattern) and FNodesByName.TryGetValue(Key(pattern), node) then
  begin
    matches.Add(node);
    Exit;
  end;

  for node in FNodes do
  begin
    matched := MatchesUnitPattern(pattern, node.Name);
    if not matched then
      for alias in node.Aliases do
        if MatchesUnitPattern(pattern, alias) then
        begin
          matched := true;
          Break;
        end;
    // one node, however many of its names matched
    if matched then
      matches.Add(node);
  end;

  matches.Sort(
    function(const left, right : TGraphNode) : integer
    begin
      result := CompareText(left.Name, right.Name);
    end);
end;

procedure TUnitGraph.Link(const map : IDictionary<string, IList<string>>;
  const fromName : string; const toName : string);
var
  neighbours : IList<string>;
  existing : string;
begin
  if not map.TryGetValue(Key(fromName), neighbours) then
  begin
    neighbours := TCollections.CreateList<string>;
    map[Key(fromName)] := neighbours;
  end;
  // Unit names are matched without regard to case everywhere else, so the same unit
  // written two ways - Winapi.Windows in one clause and WinAPi.Windows in another - is
  // one neighbour. Contains would compare them exactly and let both in, which would
  // count the unit twice in anything that walks from here.
  for existing in neighbours do
    if SameText(existing, toName) then
      Exit;
  neighbours.Add(toName);
end;

function TUnitGraph.EdgesIn(const map : IDictionary<string, IList<TGraphEdge>>;
  const unitName : string) : IReadOnlyList<TGraphEdge>;
var
  found : IList<TGraphEdge>;
begin
  if map.TryGetValue(Key(unitName), found) then
    result := found.AsReadOnly
  else
    result := TCollections.CreateList<TGraphEdge>.AsReadOnly;
end;

procedure TUnitGraph.Attach(const map : IDictionary<string, IList<TGraphEdge>>;
  const unitName : string; const edge : TGraphEdge);
var
  found : IList<TGraphEdge>;
begin
  if not map.TryGetValue(Key(unitName), found) then
  begin
    found := TCollections.CreateList<TGraphEdge>;
    map[Key(unitName)] := found;
  end;
  found.Add(edge);
end;

procedure TUnitGraph.AddEdge(const edge : TGraphEdge);
var
  edgeKey : string;
begin
  if (edge.FromUnit = '') or (edge.ToUnit = '') then
    Exit;

  // the same dependency written twice in one clause is one fact, but the same unit used
  // in both the interface and the implementation is two
  edgeKey := Format('%s|%s|%d|%d|%s', [Key(edge.FromUnit), Key(edge.ToUnit),
    Ord(edge.Section), Ord(edge.Certainty), Key(edge.Condition)]);
  if FEdgeKeys.Contains(edgeKey) then
    Exit;
  FEdgeKeys.Add(edgeKey);

  EnsureNode(edge.FromUnit);
  EnsureNode(edge.ToUnit);
  FEdges.Add(edge);

  Link(FForward, edge.FromUnit, edge.ToUnit);
  Link(FReverse, edge.ToUnit, edge.FromUnit);

  Attach(FEdgesByTarget, edge.ToUnit, edge);
  Attach(FEdgesBySource, edge.FromUnit, edge);

  // a new edge can create a shorter route, so any search already done is stale
  FSearchFrom := '';
end;

function TUnitGraph.GetNodes : IReadOnlyList<TGraphNode>;
begin
  result := FNodes.AsReadOnly;
end;

function TUnitGraph.GetEdges : IReadOnlyList<TGraphEdge>;
begin
  result := FEdges.AsReadOnly;
end;

function TUnitGraph.AdjacentTo(const map : IDictionary<string, IList<string>>;
  const unitName : string) : IReadOnlyList<string>;
var
  neighbours : IList<string>;
begin
  if map.TryGetValue(Key(unitName), neighbours) then
    result := neighbours.AsReadOnly
  else
    result := TCollections.CreateList<string>.AsReadOnly;
end;

function TUnitGraph.Dependencies(const unitName : string) : IReadOnlyList<string>;
begin
  result := AdjacentTo(FForward, unitName);
end;

function TUnitGraph.Dependents(const unitName : string) : IReadOnlyList<string>;
begin
  result := AdjacentTo(FReverse, unitName);
end;

function TUnitGraph.EdgesTo(const unitName : string) : IReadOnlyList<TGraphEdge>;
begin
  result := EdgesIn(FEdgesByTarget, unitName);
end;

function TUnitGraph.EdgesFrom(const unitName : string) : IReadOnlyList<TGraphEdge>;
begin
  result := EdgesIn(FEdgesBySource, unitName);
end;

procedure TUnitGraph.EnsureSearchFrom(const fromUnit : string);
var
  queue : IQueue<string>;
  current : string;
  neighbour : string;
begin
  if (FSearchFrom <> '') and SameText(FSearchFrom, fromUnit) then
    Exit;

  // Breadth first, so every unit is reached at its shortest depth. Recording each
  // predecessor that sits exactly one level closer builds the shortest path graph for
  // every unit at once, which is what makes answering about many of them cheap.
  FSearchDepth := TCollections.CreateDictionary<string, integer>;
  FSearchPredecessors := TCollections.CreateDictionary<string, IList<string>>;
  queue := TCollections.CreateQueue<string>;

  FSearchDepth[Key(fromUnit)] := 0;
  queue.Enqueue(fromUnit);

  while queue.Count > 0 do
  begin
    current := queue.Dequeue;
    for neighbour in Dependencies(current) do
    begin
      if not FSearchDepth.ContainsKey(Key(neighbour)) then
      begin
        FSearchDepth[Key(neighbour)] := FSearchDepth[Key(current)] + 1;
        queue.Enqueue(neighbour);
      end;

      // a predecessor only counts when it really is one step closer to the start
      if FSearchDepth[Key(neighbour)] = FSearchDepth[Key(current)] + 1 then
        Link(FSearchPredecessors, neighbour, current);
    end;
  end;

  FSearchFrom := fromUnit;
end;

function TUnitGraph.FindPaths(const fromUnit : string; const toUnit : string;
  const maxPaths : integer) : IReadOnlyList<TArray<string>>;
var
  paths : IList<TArray<string>>;
  depth : IDictionary<string, integer>;
  predecessors : IDictionary<string, IList<string>>;

  /// <summary>
  ///   Walk the predecessor chains back from the target. A predecessor is only recorded
  ///   when it sits exactly one level closer to the start, so every chain produced here
  ///   is a shortest one and the walk can never revisit a node.
  /// </summary>
  procedure Collect(const node : string; const tail : TArray<string>);
  var
    chain : TArray<string>;
    previous : string;
    predecessorList : IList<string>;
  begin
    if paths.Count >= maxPaths then
      Exit;

    chain := Concat(TArray<string>.Create(node), tail);

    if SameText(node, fromUnit) then
    begin
      paths.Add(chain);
      Exit;
    end;

    if not predecessors.TryGetValue(Key(node), predecessorList) then
      Exit;

    for previous in predecessorList do
    begin
      Collect(previous, chain);
      if paths.Count >= maxPaths then
        Exit;
    end;
  end;

begin
  paths := TCollections.CreateList<TArray<string>>;
  result := paths.AsReadOnly;

  if (maxPaths <= 0) or not ContainsNode(fromUnit) or not ContainsNode(toUnit) then
    Exit;

  if SameText(fromUnit, toUnit) then
  begin
    paths.Add(TArray<string>.Create(EnsureNode(fromUnit).Name));
    Exit;
  end;

  EnsureSearchFrom(fromUnit);
  depth := FSearchDepth;
  predecessors := FSearchPredecessors;

  if not depth.ContainsKey(Key(toUnit)) then
    Exit;

  Collect(EnsureNode(toUnit).Name, nil);
end;

function TUnitGraph.ReachableFrom(const fromUnit : string) : IReadOnlyList<string>;
var
  reached : IList<string>;
  visited : string;
  node : TGraphNode;
begin
  reached := TCollections.CreateList<string>;
  result := reached.AsReadOnly;

  if not ContainsNode(fromUnit) then
    Exit;

  // the breadth first search already records every unit it reached, so this is the
  // search it does for the chain finding, read a different way
  EnsureSearchFrom(fromUnit);
  for visited in FSearchDepth.Keys do
    if TryFindNode(visited, node) then
      reached.Add(node.Name);
end;

end.
