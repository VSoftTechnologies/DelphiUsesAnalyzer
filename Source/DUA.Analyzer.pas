unit DUA.Analyzer;

interface

uses
  System.SysUtils,
  Spring.Collections,
  DUA.Types,
  DUA.Defines,
  DUA.Graph,
  DUA.Scanner,
  DUA.SearchPath,
  DUA.Compiler.Versions;

type
  /// <summary>
  ///   Which part of the run is happening. Building the search paths walks the whole
  ///   Delphi source tree, so it is slow enough to be worth saying so.
  /// </summary>
  TAnalyzerPhase = (apReadingProject, apBuildingSearchPaths, apScanning, apFinished);

  /// <summary>
  ///   Called as the analysis proceeds so a caller can show something. scanned is the
  ///   number of units read so far and queued is how many are still waiting.
  /// </summary>
  TAnalyzerProgress = reference to procedure(const phase : TAnalyzerPhase;
                                             const scanned : integer; const queued : integer;
                                             const currentUnit : string);

  TAnalyzerOptions = record
    /// <summary>A .dproj or a .dpr - the partner file is found automatically.</summary>
    ProjectFile : string;
    Config : string;
    Platform : string;
    /// <summary>Overrides whatever the dproj implies, eg "13" or "delphi12.0".</summary>
    Compiler : string;
    OutputFile : string;
    /// <summary>Descend into the Delphi rtl and vcl sources rather than stopping there.</summary>
    Deep : boolean;
    ExtraDefines : TArray<string>;
    ExtraUndefines : TArray<string>;
    ExtraSearchPaths : TArray<string>;
    /// <summary>Optional - nil means say nothing.</summary>
    OnProgress : TAnalyzerProgress;
  end;

  IAnalysisResult = interface
    ['{4D9E0B72-3C81-4F56-A7D2-6E015B8C39A4}']
    function GetGraph : IUnitGraph;
    function GetWarnings : IReadOnlyList<TScanWarning>;
    function GetDefines : IDefineSet;
    function GetResolver : IUnitResolver;
    function GetProjectFile : string;
    function GetDprFile : string;
    function GetRootUnit : string;
    function GetCompiler : TCompilerVersion;
    function GetPlatform : TDelphiPlatform;
    function GetConfig : string;
    function GetAppType : string;
    function GetProjectVersion : string;
    function GetUnresolvedCount : integer;

    property Graph : IUnitGraph read GetGraph;
    property Warnings : IReadOnlyList<TScanWarning> read GetWarnings;
    property Defines : IDefineSet read GetDefines;
    property Resolver : IUnitResolver read GetResolver;
    property ProjectFile : string read GetProjectFile;
    property DprFile : string read GetDprFile;
    property RootUnit : string read GetRootUnit;
    property Compiler : TCompilerVersion read GetCompiler;
    property Platform : TDelphiPlatform read GetPlatform;
    property Config : string read GetConfig;
    /// <summary>Console or Application, from the dproj. Empty when there is no dproj.</summary>
    property AppType : string read GetAppType;
    property ProjectVersion : string read GetProjectVersion;
    property UnresolvedCount : integer read GetUnresolvedCount;
  end;

  EAnalyzerError = class(Exception);

  IAnalyzer = interface
    ['{6A2F51C8-7E34-4D09-B18F-05C7A3E926D1}']
    /// <summary>
    ///   Work out what is being targeted and where units will be looked for, without
    ///   reading a line of source. Split out from the walk so a caller can show the
    ///   target before starting something that takes a while.
    /// </summary>
    function Prepare(const options : TAnalyzerOptions) : IAnalysisResult;
    /// <summary>Walk from the dpr. Takes a result that Prepare produced.</summary>
    procedure Walk(const prepared : IAnalysisResult; const options : TAnalyzerOptions);
    /// <summary>Prepare then Walk.</summary>
    function Analyze(const options : TAnalyzerOptions) : IAnalysisResult;
  end;

  /// <summary>
  ///   A plain holder for everything an analysis produced. Public so that a graph read
  ///   back from json can be presented exactly like one that was just walked.
  /// </summary>
  TAnalysisResult = class(TInterfacedObject, IAnalysisResult)
  public
    Graph : IUnitGraph;
    Warnings : IList<TScanWarning>;
    Defines : IDefineSet;
    Resolver : IUnitResolver;
    ProjectFile : string;
    DprFile : string;
    RootUnit : string;
    Compiler : TCompilerVersion;
    Platform : TDelphiPlatform;
    Config : string;
    AppType : string;
    ProjectVersion : string;
    /// <summary>Carried from Prepare to Walk so the scanner can follow {$I}.</summary>
    IncludeResolver : IIncludeResolver;
  protected
    function GetGraph : IUnitGraph;
    function GetWarnings : IReadOnlyList<TScanWarning>;
    function GetDefines : IDefineSet;
    function GetResolver : IUnitResolver;
    function GetProjectFile : string;
    function GetDprFile : string;
    function GetRootUnit : string;
    function GetCompiler : TCompilerVersion;
    function GetPlatform : TDelphiPlatform;
    function GetConfig : string;
    function GetAppType : string;
    function GetProjectVersion : string;
    function GetUnresolvedCount : integer;
  public
    constructor Create;
    procedure Warn(const fileName : string; const line : integer; const message : string);
  end;

  TAnalyzer = class(TInterfacedObject, IAnalyzer)
  protected
    function Prepare(const options : TAnalyzerOptions) : IAnalysisResult;
    procedure Walk(const prepared : IAnalysisResult; const options : TAnalyzerOptions);
    function Analyze(const options : TAnalyzerOptions) : IAnalysisResult;
  end;

implementation

uses
  System.IOUtils,
  DUA.Compiler.Environment,
  DUA.Project.DProj,
  DUA.Project.MSBuild;

type
  /// <summary>
  ///   Resolves {$I} directives against the folder of the file doing the including and
  ///   then the project search paths, which is the order the compiler uses.
  /// </summary>
  TIncludeResolver = class(TInterfacedObject, IIncludeResolver)
  private
    FFolders : IList<string>;
    function TryFolder(const folder : string; const fileName : string;
                       out resolvedFileName : string) : boolean;
  protected
    function TryResolve(const parentFileName : string; const includeName : string;
                        out resolvedFileName : string; out content : string) : boolean;
  public
    constructor Create;
    procedure AddFolder(const folder : string);
  end;

{ TIncludeResolver }

constructor TIncludeResolver.Create;
begin
  inherited Create;
  FFolders := TCollections.CreateList<string>;
end;

procedure TIncludeResolver.AddFolder(const folder : string);
var
  normalised : string;
begin
  normalised := ExcludeTrailingPathDelimiter(Trim(folder));
  if (normalised <> '') and not FFolders.Contains(normalised) then
    FFolders.Add(normalised);
end;

function TIncludeResolver.TryFolder(const folder : string; const fileName : string;
  out resolvedFileName : string) : boolean;
var
  full : string;
begin
  resolvedFileName := '';
  if folder = '' then
    Exit(false);
  full := TPath.Combine(folder, fileName);
  result := TFile.Exists(full);
  if result then
    resolvedFileName := TPath.GetFullPath(full);
end;

function TIncludeResolver.TryResolve(const parentFileName : string; const includeName : string;
  out resolvedFileName : string; out content : string) : boolean;
var
  candidate : string;
  folder : string;
  names : TArray<string>;
  name : string;
begin
  resolvedFileName := '';
  content := '';

  candidate := Trim(includeName);
  if candidate = '' then
    Exit(false);

  // an include written without an extension means .inc
  if ExtractFileExt(candidate) = '' then
    names := TArray<string>.Create(candidate + '.inc', candidate)
  else
    names := TArray<string>.Create(candidate);

  for name in names do
  begin
    if TPath.IsPathRooted(name) and TFile.Exists(name) then
    begin
      resolvedFileName := TPath.GetFullPath(name);
      Break;
    end;

    if TryFolder(ExcludeTrailingPathDelimiter(ExtractFilePath(parentFileName)), name, resolvedFileName) then
      Break;

    for folder in FFolders do
      if TryFolder(folder, name, resolvedFileName) then
        Break;

    if resolvedFileName <> '' then
      Break;
  end;

  result := resolvedFileName <> '';
  if result then
    try
      content := TFile.ReadAllText(resolvedFileName);
    except
      // an unreadable include is a missing one as far as the caller cares
      result := false;
      resolvedFileName := '';
    end;
end;

{ TAnalysisResult }

constructor TAnalysisResult.Create;
begin
  inherited Create;
  Graph := TUnitGraph.Create;
  Warnings := TCollections.CreateList<TScanWarning>;
end;

procedure TAnalysisResult.Warn(const fileName : string; const line : integer; const message : string);
var
  warning : TScanWarning;
begin
  warning.FileName := fileName;
  warning.Line := line;
  warning.Message := message;
  Warnings.Add(warning);
end;

function TAnalysisResult.GetGraph : IUnitGraph;
begin
  result := Graph;
end;

function TAnalysisResult.GetWarnings : IReadOnlyList<TScanWarning>;
begin
  result := Warnings.AsReadOnly;
end;

function TAnalysisResult.GetDefines : IDefineSet;
begin
  result := Defines;
end;

function TAnalysisResult.GetResolver : IUnitResolver;
begin
  result := Resolver;
end;

function TAnalysisResult.GetProjectFile : string;
begin
  result := ProjectFile;
end;

function TAnalysisResult.GetDprFile : string;
begin
  result := DprFile;
end;

function TAnalysisResult.GetRootUnit : string;
begin
  result := RootUnit;
end;

function TAnalysisResult.GetCompiler : TCompilerVersion;
begin
  result := Compiler;
end;

function TAnalysisResult.GetPlatform : TDelphiPlatform;
begin
  result := Platform;
end;

function TAnalysisResult.GetConfig : string;
begin
  result := Config;
end;

function TAnalysisResult.GetAppType : string;
begin
  result := AppType;
end;

function TAnalysisResult.GetProjectVersion : string;
begin
  result := ProjectVersion;
end;

function TAnalysisResult.GetUnresolvedCount : integer;
var
  node : TGraphNode;
begin
  result := 0;
  for node in Graph.Nodes do
    if node.Kind = ukUnresolved then
      Inc(result);
end;

{ TAnalyzer }

function TAnalyzer.Prepare(const options : TAnalyzerOptions) : IAnalysisResult;
var
  analysis : TAnalysisResult;
  environment : IDelphiEnvironment;
  reader : IDProjReader;
  project : IProjectInfo;
  properties : IMSBuildProperties;
  includes : TIncludeResolver;
  namespaces : string;
  entry : string;
  candidates : string;
  sourceFile : string;
  searchFolder : string;

  procedure Report(const phase : TAnalyzerPhase);
  begin
    if Assigned(options.OnProgress) then
      options.OnProgress(phase, 0, 0, '');
  end;

  procedure AddSearchFolder(const folder : string; const origin : TUnitOrigin);
  begin
    if Trim(folder) = '' then
      Exit;
    analysis.Resolver.AddSearchPath(folder, origin);
    includes.AddFolder(folder);
  end;

begin
  analysis := TAnalysisResult.Create;
  result := analysis;

  if Trim(options.ProjectFile) = '' then
    raise EAnalyzerError.Create('no project file given');
  if not TFile.Exists(options.ProjectFile) then
    raise EAnalyzerError.CreateFmt('project file not found: %s', [options.ProjectFile]);

  analysis.ProjectFile := TPath.GetFullPath(options.ProjectFile);
  Report(apReadingProject);
  environment := TDelphiEnvironment.Create;
  reader := TDProjReader.Create;
  project := nil;

  // --- locate the dproj and the dpr, given either one ---
  if SameText(ExtractFileExt(analysis.ProjectFile), '.dproj') then
  begin
    project := reader.ReadFile(analysis.ProjectFile);
    analysis.DprFile := project.MainSource;
  end
  else
  begin
    analysis.DprFile := analysis.ProjectFile;
    // the sibling dproj is where the search paths live, so it is worth a lot
    if TFile.Exists(ChangeFileExt(analysis.ProjectFile, '.dproj')) then
    begin
      analysis.ProjectFile := ChangeFileExt(analysis.ProjectFile, '.dproj');
      project := reader.ReadFile(analysis.ProjectFile);
    end
    else
      analysis.Warn(analysis.ProjectFile, 0,
        'no matching dproj, so only the search paths given on the command line are used');
  end;

  if (analysis.DprFile = '') or not TFile.Exists(analysis.DprFile) then
    raise EAnalyzerError.CreateFmt('could not find the program source for %s', [analysis.ProjectFile]);

  // --- decide what we are targeting ---
  analysis.Config := options.Config;
  analysis.Platform := TDelphiPlatforms.Parse(options.Platform);
  analysis.Compiler := TCompilerVersions.Parse(options.Compiler);

  if project <> nil then
  begin
    if analysis.Config = '' then
      analysis.Config := project.DefaultConfig;
    if analysis.Platform = dpUnknown then
      analysis.Platform := TDelphiPlatforms.Parse(project.DefaultPlatform);

    // dpm writes the exact compiler into the dproj, which beats guessing from anything
    if analysis.Compiler = cvUnknown then
      analysis.Compiler := TCompilerVersions.Parse(project.DpmCompiler);

    if analysis.Compiler = cvUnknown then
    begin
      analysis.Compiler := TCompilerVersions.FromProjectVersion(project.ProjectVersion);
      if TCompilerVersions.IsAmbiguousProjectVersion(project.ProjectVersion, candidates) then
        analysis.Warn(analysis.ProjectFile, 0, Format(
          'ProjectVersion %s is written by %s - assuming %s, pass --compiler to be sure',
          [project.ProjectVersion, candidates, TCompilerVersions.ToDisplayName(analysis.Compiler)]));
    end;
  end;

  if analysis.Config = '' then
    analysis.Config := 'Debug';
  if analysis.Platform = dpUnknown then
    analysis.Platform := dpWin32;
  if analysis.Compiler = cvUnknown then
  begin
    analysis.Compiler := environment.NewestInstalled;
    if analysis.Compiler <> cvUnknown then
      analysis.Warn(analysis.ProjectFile, 0, Format(
        'could not tell which Delphi this project targets, assuming %s',
        [TCompilerVersions.ToDisplayName(analysis.Compiler)]));
  end;
  if analysis.Compiler = cvUnknown then
    raise EAnalyzerError.Create('could not determine the Delphi version, pass --compiler');

  if project <> nil then
  begin
    properties := project.GetProperties(analysis.Config, TDelphiPlatforms.ToName(analysis.Platform));
    analysis.AppType := project.AppType;
    analysis.ProjectVersion := project.ProjectVersion;
  end
  else
    properties := TMSBuildProperties.Create;

  // --- the conditional symbols the compiler would predefine ---
  analysis.Defines := TDefineSet.Create;
  TCompilerDefines.Seed(analysis.Defines, analysis.Compiler, analysis.Platform,
    (project = nil) or SameText(project.AppType, 'Console'));

  for entry in properties.GetValue('DCC_Define').Split([';']) do
    if Trim(entry) <> '' then
      analysis.Defines.Define(Trim(entry));

  for entry in options.ExtraDefines do
    analysis.Defines.Define(Trim(entry));
  for entry in options.ExtraUndefines do
    analysis.Defines.Undefine(Trim(entry));

  // --- where units are looked for, in the order the compiler would look ---
  Report(apBuildingSearchPaths);
  analysis.Resolver := TUnitResolver.Create;
  includes := TIncludeResolver.Create;
  // the scanner needs this later to follow {$I}, so it travels with the result
  analysis.IncludeResolver := includes;

  AddSearchFolder(ExtractFilePath(analysis.DprFile), uoProject);
  if project <> nil then
  begin
    AddSearchFolder(project.ProjectDir, uoProject);
    // a unit listed in the dproj may live in a folder no search path mentions
    for sourceFile in project.SourceFiles do
      AddSearchFolder(ExtractFilePath(sourceFile), uoProject);
  end;

  for entry in options.ExtraSearchPaths do
    AddSearchFolder(entry, uoProject);

  for entry in properties.GetValue('DCC_UnitSearchPath').Split([';']) do
  begin
    if Trim(entry) = '' then
      Continue;
    if TPath.IsPathRooted(Trim(entry)) then
      searchFolder := Trim(entry)
    else if project <> nil then
      searchFolder := TPath.Combine(project.ProjectDir, Trim(entry))
    else
      searchFolder := TPath.Combine(ExtractFilePath(analysis.DprFile), Trim(entry));

    searchFolder := TPath.GetFullPath(searchFolder);
    // a dpm package path lands here too, and is worth telling apart in the output
    if searchFolder.ToLower.Contains('package_cache') or searchFolder.ToLower.Contains('.dpm') then
      AddSearchFolder(searchFolder, uoPackage)
    else
      AddSearchFolder(searchFolder, uoProject);
  end;

  for searchFolder in environment.GetLibraryPath(analysis.Compiler, analysis.Platform) do
    AddSearchFolder(searchFolder, uoLibrary);

  // the rtl and vcl sources, so those units resolve to real files and classify properly
  for searchFolder in environment.GetSourceFolders(analysis.Compiler) do
    AddSearchFolder(searchFolder, uoRTL);

  namespaces := properties.GetValue('DCC_Namespace');
  if Trim(namespaces) <> '' then
    analysis.Resolver.AddNamespaces(namespaces);
  analysis.Resolver.AddNamespaces(TCompilerDefines.DefaultNamespaces(analysis.Platform));
end;

procedure TAnalyzer.Walk(const prepared : IAnalysisResult; const options : TAnalyzerOptions);
var
  analysis : TAnalysisResult;
  scanner : IUnitScanner;
  pending : IQueue<string>;
  scanned : ISet<string>;
  scanCount : integer;
  rootNode : TGraphNode;

  procedure Report(const phase : TAnalyzerPhase; const currentUnit : string);
  begin
    if Assigned(options.OnProgress) then
      options.OnProgress(phase, scanCount, pending.Count, currentUnit);
  end;

  /// <summary>
  ///   Scan one file, record what it uses, and queue anything worth descending into.
  ///   Returns the name from the unit header, so the caller can name the root node.
  /// </summary>
  function ScanUnit(const unitName : string; const fileName : string) : string;
  var
    scanResult : IScanResult;
    usesEntry : TUsesEntry;
    resolved : TResolvedUnit;
    edge : TGraphEdge;
    node : TGraphNode;
    targetNode : TGraphNode;
    warning : TScanWarning;
    source : string;
    targetName : string;
    inPath : string;
  begin
    result := unitName;
    try
      source := TFile.ReadAllText(fileName);
    except
      on e : Exception do
      begin
        analysis.Warn(fileName, 0, 'could not read: ' + e.Message);
        Exit;
      end;
    end;

    scanResult := scanner.Scan(source, fileName, analysis.Defines);
    if scanResult.UnitName <> '' then
      result := scanResult.UnitName;

    node := analysis.Graph.EnsureNode(result);
    result := node.Name;
    node.FileName := fileName;
    node.Parsed := true;

    for warning in scanResult.Warnings do
      analysis.Warnings.Add(warning);

    // A dpr says outright where its units live, so register every `in` path before
    // resolving any of them - the last entry may be the one the first entry uses.
    for usesEntry in scanResult.Entries do
      if usesEntry.InPath <> '' then
      begin
        inPath := usesEntry.InPath;
        if not TPath.IsPathRooted(inPath) then
          inPath := TPath.Combine(ExtractFilePath(fileName), inPath);
        analysis.Resolver.AddExplicitUnit(usesEntry.UnitName, TPath.GetFullPath(inPath));
      end;

    for usesEntry in scanResult.Entries do
    begin
      targetName := usesEntry.UnitName;

      if analysis.Resolver.TryResolve(usesEntry.UnitName, fileName, resolved) then
      begin
        targetNode := analysis.Graph.EnsureNode(resolved.UnitName);
        // the node owns the canonical spelling, so an edge always names it exactly -
        // source files spell the same unit several ways and the graph should not
        targetName := targetNode.Name;
        targetNode.FileName := resolved.FileName;
        targetNode.Kind := UnitOriginToKind(resolved.Origin);

        // remember the source said Classes where the compiler means System.Classes
        if not SameText(usesEntry.UnitName, targetName) and
           not targetNode.Aliases.Contains(usesEntry.UnitName) then
          targetNode.Aliases.Add(usesEntry.UnitName);

        // rtl and vcl units are recorded but not opened: their internals are not
        // something anyone can act on, and they multiply the graph enormously
        if resolved.IsSource and (options.Deep or (resolved.Origin <> uoRTL)) and
           not scanned.Contains(UpperCase(targetName)) then
          pending.Enqueue(targetName);
      end
      else
        analysis.Graph.EnsureNode(targetName).Kind := ukUnresolved;

      edge := Default(TGraphEdge);
      edge.FromUnit := result;
      edge.ToUnit := targetName;
      edge.Section := usesEntry.Section;
      edge.Certainty := usesEntry.Certainty;
      edge.Condition := usesEntry.Condition;
      edge.FileName := usesEntry.FileName;
      edge.Line := usesEntry.Line;
      analysis.Graph.AddEdge(edge);
    end;
  end;

  procedure DrainQueue;
  var
    next : string;
    node : TGraphNode;
  begin
    while pending.Count > 0 do
    begin
      next := pending.Dequeue;
      if scanned.Contains(UpperCase(next)) then
        Continue;
      scanned.Add(UpperCase(next));

      if not analysis.Graph.TryFindNode(next, node) then
        Continue;
      if (node.FileName = '') or not SameText(ExtractFileExt(node.FileName), '.pas') then
        Continue;

      ScanUnit(next, node.FileName);
      Inc(scanCount);
      Report(apScanning, next);
    end;
  end;

begin
  analysis := prepared as TAnalysisResult;
  if analysis.Resolver = nil then
    raise EAnalyzerError.Create('Walk needs a result from Prepare');

  scanCount := 0;
  pending := TCollections.CreateQueue<string>;
  scanned := TCollections.CreateSet<string>;
  scanner := TUnitScanner.Create(analysis.IncludeResolver);

  Report(apScanning, '');

  analysis.RootUnit := ScanUnit(ChangeFileExt(ExtractFileName(analysis.DprFile), ''), analysis.DprFile);
  scanned.Add(UpperCase(analysis.RootUnit));

  if analysis.Graph.TryFindNode(analysis.RootUnit, rootNode) then
    rootNode.Kind := ukProgram;

  Inc(scanCount);
  DrainQueue;
  Report(apFinished, '');
end;

function TAnalyzer.Analyze(const options : TAnalyzerOptions) : IAnalysisResult;
begin
  result := Prepare(options);
  Walk(result, options);
end;

end.
