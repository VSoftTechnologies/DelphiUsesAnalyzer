unit DUA.SearchPath;

interface

uses
  Spring.Collections,
  DUA.Types;

type
  /// <summary>Where a search path came from, which becomes the node kind in the output.</summary>
  TUnitOrigin = (uoProject, uoPackage, uoLibrary, uoRTL);

  TSearchPathEntry = record
    Path : string;
    Origin : TUnitOrigin;
  end;

  TResolvedUnit = record
    /// <summary>
    ///   The name the compiler would use. When an unqualified name resolved through a
    ///   unit scope this is the qualified form, so Classes becomes System.Classes.
    /// </summary>
    UnitName : string;
    FileName : string;
    Origin : TUnitOrigin;
    /// <summary>False when only a dcu was found, so the unit cannot be parsed.</summary>
    IsSource : boolean;
  end;

  IUnitResolver = interface
    ['{5C1A7E38-9D64-4B0F-A2E7-8F3B6D19C042}']
    procedure AddSearchPath(const path : string; const origin : TUnitOrigin);
    /// <summary>Add unit scope names, as a semicolon separated DCC_Namespace value.</summary>
    procedure AddNamespaces(const namespaces : string);
    /// <summary>
    ///   Register the path a dpr gave in its `in` clause. These win over the search
    ///   paths, exactly as they do for the compiler.
    /// </summary>
    procedure AddExplicitUnit(const unitName : string; const fileName : string);

    function TryResolve(const unitName : string; const referencingFile : string;
                        out resolved : TResolvedUnit) : boolean;

    function GetSearchPaths : IReadOnlyList<TSearchPathEntry>;
    function GetNamespaces : IReadOnlyList<string>;
    property SearchPaths : IReadOnlyList<TSearchPathEntry> read GetSearchPaths;
    property Namespaces : IReadOnlyList<string> read GetNamespaces;
  end;

  TUnitResolver = class(TInterfacedObject, IUnitResolver)
  private type
    /// <summary>
    ///   The names to try for one used name, in the order the compiler would try them,
    ///   with the file names pre-lowercased. Built once per name and reused for every
    ///   folder, because rebuilding it per folder is what made resolution quadratic.
    /// </summary>
    TCandidates = record
      Names : TArray<string>;
      PasFiles : TArray<string>;
      DcuFiles : TArray<string>;
    end;

    TCachedResolution = record
      Found : boolean;
      Value : TResolvedUnit;
    end;
  private
    FSearchPaths : IList<TSearchPathEntry>;
    /// <summary>Runs alongside FSearchPaths, filled lazily, so a probe needs no hashing.</summary>
    FPathIndexes : IList<IDictionary<string, string>>;
    FNamespaces : IList<string>;
    FExplicitUnits : IDictionary<string, string>;
    /// <summary>Listings of folders that are not search paths, ie a referencing unit's own.</summary>
    FFolderIndexes : IDictionary<string, IDictionary<string, string>>;
    FCandidateCache : IDictionary<string, TCandidates>;
    /// <summary>
    ///   What the search paths answered for a name and extension. The search paths do
    ///   not depend on who is asking, so this is safe to share - and on a real project
    ///   the same handful of units are used by hundreds of others.
    /// </summary>
    FSearchPathCache : IDictionary<string, TCachedResolution>;
    function BuildIndex(const folder : string) : IDictionary<string, string>;
    function FolderIndex(const folder : string) : IDictionary<string, string>;
    function PathIndex(const position : integer) : IDictionary<string, string>;
    function CandidatesFor(const unitName : string) : TCandidates;
    function ProbeIndex(const index : IDictionary<string, string>; const candidates : TCandidates;
                        const wantSource : boolean; const origin : TUnitOrigin;
                        out resolved : TResolvedUnit) : boolean;
    function TryResolveOnSearchPaths(const unitName : string; const candidates : TCandidates;
                                     const wantSource : boolean; out resolved : TResolvedUnit) : boolean;
    procedure InvalidateCaches;
  protected
    procedure AddSearchPath(const path : string; const origin : TUnitOrigin);
    procedure AddNamespaces(const namespaces : string);
    procedure AddExplicitUnit(const unitName : string; const fileName : string);
    function TryResolve(const unitName : string; const referencingFile : string;
                        out resolved : TResolvedUnit) : boolean;
    function GetSearchPaths : IReadOnlyList<TSearchPathEntry>;
    function GetNamespaces : IReadOnlyList<string>;
  public
    constructor Create;
  end;

function UnitOriginToKind(const origin : TUnitOrigin) : TUnitKind;

implementation

uses
  System.IOUtils,
  System.SysUtils;

function UnitOriginToKind(const origin : TUnitOrigin) : TUnitKind;
begin
  case origin of
    uoPackage : result := ukPackage;
    uoLibrary : result := ukLibrary;
    uoRTL : result := ukRTL;
  else
    result := ukProject;
  end;
end;

function NormaliseFolder(const path : string) : string;
begin
  result := ExcludeTrailingPathDelimiter(Trim(path));
end;

{ TUnitResolver }

constructor TUnitResolver.Create;
begin
  inherited Create;
  FSearchPaths := TCollections.CreateList<TSearchPathEntry>;
  FPathIndexes := TCollections.CreateList<IDictionary<string, string>>;
  FNamespaces := TCollections.CreateList<string>;
  FExplicitUnits := TCollections.CreateDictionary<string, string>;
  FFolderIndexes := TCollections.CreateDictionary<string, IDictionary<string, string>>;
  FCandidateCache := TCollections.CreateDictionary<string, TCandidates>;
  FSearchPathCache := TCollections.CreateDictionary<string, TCachedResolution>;
end;

procedure TUnitResolver.InvalidateCaches;
begin
  // adding a path or a scope changes what every name resolves to
  FCandidateCache.Clear;
  FSearchPathCache.Clear;
end;

procedure TUnitResolver.AddSearchPath(const path : string; const origin : TUnitOrigin);
var
  entry : TSearchPathEntry;
  existing : TSearchPathEntry;
  normalised : string;
begin
  normalised := NormaliseFolder(path);
  if normalised = '' then
    Exit;

  // the earlier path is the one the compiler would use, so a repeat adds nothing
  for existing in FSearchPaths do
    if SameText(existing.Path, normalised) then
      Exit;

  entry.Path := normalised;
  entry.Origin := origin;
  FSearchPaths.Add(entry);
  FPathIndexes.Add(nil);
  InvalidateCaches;
end;

procedure TUnitResolver.AddNamespaces(const namespaces : string);
var
  entry : string;
  trimmed : string;
begin
  for entry in namespaces.Split([';']) do
  begin
    trimmed := Trim(entry);
    // an unexpanded $(DCC_Namespace) leaves empty entries behind
    if (trimmed = '') or FNamespaces.Contains(trimmed) then
      Continue;
    FNamespaces.Add(trimmed);
    InvalidateCaches;
  end;
end;

procedure TUnitResolver.AddExplicitUnit(const unitName : string; const fileName : string);
begin
  if (unitName = '') or (fileName = '') then
    Exit;
  FExplicitUnits[LowerCase(unitName)] := fileName;
  InvalidateCaches;
end;

function TUnitResolver.BuildIndex(const folder : string) : IDictionary<string, string>;
var
  fileName : string;
begin
  result := TCollections.CreateDictionary<string, string>;
  if not TDirectory.Exists(folder) then
    Exit;

  for fileName in TDirectory.GetFiles(folder, '*', TSearchOption.soTopDirectoryOnly) do
    result[LowerCase(ExtractFileName(fileName))] := fileName;
end;

function TUnitResolver.FolderIndex(const folder : string) : IDictionary<string, string>;
begin
  if FFolderIndexes.TryGetValue(LowerCase(folder), result) then
    Exit;
  result := BuildIndex(folder);
  FFolderIndexes[LowerCase(folder)] := result;
end;

function TUnitResolver.PathIndex(const position : integer) : IDictionary<string, string>;
begin
  result := FPathIndexes[position];
  if result = nil then
  begin
    result := BuildIndex(FSearchPaths[position].Path);
    FPathIndexes[position] := result;
  end;
end;

function TUnitResolver.CandidatesFor(const unitName : string) : TCandidates;
var
  key : string;
  names : IList<string>;
  prefix : string;
  index : integer;
begin
  key := LowerCase(unitName);
  if FCandidateCache.TryGetValue(key, result) then
    Exit;

  names := TCollections.CreateList<string>;
  // the compiler always tries the name exactly as written first
  names.Add(unitName);

  // A unit scope applies whether or not the name already has dots in it, which is what
  // makes `uses Generics.Defaults` find System.Generics.Defaults. Only trying this for
  // bare names would miss most partially qualified references in real code.
  for prefix in FNamespaces do
    if not names.Contains(prefix + '.' + unitName) then
      names.Add(prefix + '.' + unitName);

  result.Names := names.ToArray;
  SetLength(result.PasFiles, Length(result.Names));
  SetLength(result.DcuFiles, Length(result.Names));
  for index := 0 to High(result.Names) do
  begin
    result.PasFiles[index] := LowerCase(result.Names[index]) + '.pas';
    result.DcuFiles[index] := LowerCase(result.Names[index]) + '.dcu';
  end;

  FCandidateCache[key] := result;
end;

function TUnitResolver.ProbeIndex(const index : IDictionary<string, string>;
  const candidates : TCandidates; const wantSource : boolean; const origin : TUnitOrigin;
  out resolved : TResolvedUnit) : boolean;
var
  position : integer;
  fullPath : string;
begin
  if index.Count > 0 then
    for position := 0 to High(candidates.Names) do
    begin
      if wantSource then
      begin
        if not index.TryGetValue(candidates.PasFiles[position], fullPath) then
          Continue;
      end
      else if not index.TryGetValue(candidates.DcuFiles[position], fullPath) then
        Continue;

      resolved.UnitName := candidates.Names[position];
      resolved.FileName := fullPath;
      resolved.Origin := origin;
      resolved.IsSource := wantSource;
      Exit(true);
    end;

  resolved := Default(TResolvedUnit);
  result := false;
end;

function TUnitResolver.TryResolveOnSearchPaths(const unitName : string;
  const candidates : TCandidates; const wantSource : boolean;
  out resolved : TResolvedUnit) : boolean;
var
  key : string;
  cached : TCachedResolution;
  position : integer;
begin
  if wantSource then
    key := LowerCase(unitName) + '|pas'
  else
    key := LowerCase(unitName) + '|dcu';

  if FSearchPathCache.TryGetValue(key, cached) then
  begin
    resolved := cached.Value;
    Exit(cached.Found);
  end;

  result := false;
  for position := 0 to FSearchPaths.Count - 1 do
    if ProbeIndex(PathIndex(position), candidates, wantSource,
                  FSearchPaths[position].Origin, resolved) then
    begin
      result := true;
      Break;
    end;

  cached.Found := result;
  cached.Value := resolved;
  FSearchPathCache[key] := cached;
end;

function TUnitResolver.TryResolve(const unitName : string; const referencingFile : string;
  out resolved : TResolvedUnit) : boolean;
var
  explicitPath : string;
  referencingFolder : string;
  candidates : TCandidates;
  wantSource : boolean;
begin
  resolved := Default(TResolvedUnit);
  if Trim(unitName) = '' then
    Exit(false);

  // 1. a dpr said exactly where this unit lives
  if FExplicitUnits.TryGetValue(LowerCase(unitName), explicitPath) and TFile.Exists(explicitPath) then
  begin
    resolved.UnitName := unitName;
    resolved.FileName := explicitPath;
    resolved.Origin := uoProject;
    resolved.IsSource := SameText(ExtractFileExt(explicitPath), '.pas');
    Exit(true);
  end;

  referencingFolder := '';
  if referencingFile <> '' then
    referencingFolder := NormaliseFolder(ExtractFilePath(referencingFile));

  candidates := CandidatesFor(unitName);

  // Source is worth more than a dcu wherever it is: a dcu ends the walk, so we would
  // rather reach the real thing on a later path than stop at a binary on an early one.
  for wantSource := true downto false do
  begin
    // 2. the folder of the unit doing the using
    if (referencingFolder <> '') and
       ProbeIndex(FolderIndex(referencingFolder), candidates, wantSource, uoProject, resolved) then
      Exit(true);

    // 3. the search paths, in order
    if TryResolveOnSearchPaths(unitName, candidates, wantSource, resolved) then
      Exit(true);
  end;

  resolved := Default(TResolvedUnit);
  result := false;
end;

function TUnitResolver.GetSearchPaths : IReadOnlyList<TSearchPathEntry>;
begin
  result := FSearchPaths.AsReadOnly;
end;

function TUnitResolver.GetNamespaces : IReadOnlyList<string>;
begin
  result := FNamespaces.AsReadOnly;
end;

end.
