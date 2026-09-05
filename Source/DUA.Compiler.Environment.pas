unit DUA.Compiler.Environment;

interface

uses
  Spring.Collections,
  DUA.Compiler.Versions;

type
  /// <summary>
  ///   Where a Delphi installation lives, and the tokens its paths are written in.
  ///   Separated from the registry lookups so the token expansion - which is where the
  ///   bugs are - can be tested without an installed Delphi.
  /// </summary>
  TBdsTokens = record
  public
    /// <summary>
    ///   Expand the $(BDS...) tokens the IDE writes into library paths, plus $(Platform)
    ///   and %ENVIRONMENT% variables. The IDE library path is stored unexpanded, so
    ///   without this every entry in it is a directory that does not exist.
    /// </summary>
    class function Expand(const value : string; const rootDir : string;
                          const bdsVersion : string; const platformName : string) : string; static;
  end;

  IDelphiEnvironment = interface
    ['{3F8B1D64-2A79-4E05-B3C8-9D6E15A72B40}']
    /// <summary>Installation folder, with a trailing delimiter. Empty when not installed.</summary>
    function GetRootDir(const compiler : TCompilerVersion) : string;
    function IsInstalled(const compiler : TCompilerVersion) : boolean;
    /// <summary>The newest installed release, or cvUnknown when none is found.</summary>
    function NewestInstalled : TCompilerVersion;
    /// <summary>
    ///   The IDE library path for a platform, split and fully expanded. These are dcu
    ///   folders as often as source folders.
    /// </summary>
    function GetLibraryPath(const compiler : TCompilerVersion;
                            const targetPlatform : TDelphiPlatform) : IReadOnlyList<string>;
    /// <summary>Every folder under the installation's source tree, for resolving rtl and vcl units.</summary>
    function GetSourceFolders(const compiler : TCompilerVersion) : IReadOnlyList<string>;
  end;

  TDelphiEnvironment = class(TInterfacedObject, IDelphiEnvironment)
  private
    FRootDirs : IDictionary<integer, string>;
    FSourceFolders : IDictionary<integer, IReadOnlyList<string>>;
  protected
    function GetRootDir(const compiler : TCompilerVersion) : string;
    function IsInstalled(const compiler : TCompilerVersion) : boolean;
    function NewestInstalled : TCompilerVersion;
    function GetLibraryPath(const compiler : TCompilerVersion;
                            const targetPlatform : TDelphiPlatform) : IReadOnlyList<string>;
    function GetSourceFolders(const compiler : TCompilerVersion) : IReadOnlyList<string>;
  public
    constructor Create;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils,
  System.Win.Registry,
  Winapi.Windows;

{ helpers }

/// <summary>
///   Expand %NAME% variables. Winapi only offers the raw api, which needs a buffer
///   sized by a first call that returns the required length.
/// </summary>
function ExpandEnvironment(const value : string) : string;
var
  required : DWORD;
  buffer : string;
begin
  if (value = '') or (Pos('%', value) = 0) then
    Exit(value);

  required := Winapi.Windows.ExpandEnvironmentStrings(PChar(value), nil, 0);
  if required = 0 then
    Exit(value);

  SetLength(buffer, required);
  required := Winapi.Windows.ExpandEnvironmentStrings(PChar(value), PChar(buffer), required);
  if required = 0 then
    Exit(value);

  // the returned length includes the terminating null
  result := Copy(buffer, 1, required - 1);
end;

{ TBdsTokens }

class function TBdsTokens.Expand(const value : string; const rootDir : string;
  const bdsVersion : string; const platformName : string) : string;
var
  root : string;
  publicDocuments : string;
  userDocuments : string;

  procedure Replace(const token : string; const replacement : string);
  begin
    result := StringReplace(result, token, replacement, [rfReplaceAll, rfIgnoreCase]);
  end;

begin
  result := value;
  if result = '' then
    Exit;

  root := ExcludeTrailingPathDelimiter(rootDir);
  publicDocuments := ExpandEnvironment('%PUBLIC%') +
    '\Documents\Embarcadero\Studio\' + bdsVersion;
  userDocuments := ExpandEnvironment('%USERPROFILE%') +
    '\Documents\Embarcadero\Studio\' + bdsVersion;

  // longest tokens first, so that $(BDSLIB) is not eaten by $(BDS)
  Replace('$(BDSCATALOGREPOSITORY)', userDocuments + '\CatalogRepository');
  Replace('$(BDSPROJECTSDIR)', userDocuments + '\Projects');
  Replace('$(BDSCOMMONDIR)', publicDocuments);
  Replace('$(BDSUSERDIR)', userDocuments);
  Replace('$(BDSINCLUDE)', root + '\include');
  Replace('$(BDSLIB)', root + '\lib');
  Replace('$(BDSBIN)', root + '\bin');
  Replace('$(BDS)', root);
  Replace('$(PLATFORM)', platformName);

  result := ExpandEnvironment(result);
end;

{ TDelphiEnvironment }

constructor TDelphiEnvironment.Create;
begin
  inherited Create;
  FRootDirs := TCollections.CreateDictionary<integer, string>;
  FSourceFolders := TCollections.CreateDictionary<integer, IReadOnlyList<string>>;
end;

function TDelphiEnvironment.GetRootDir(const compiler : TCompilerVersion) : string;
var
  registry : TRegistry;
  key : string;
begin
  if FRootDirs.TryGetValue(Ord(compiler), result) then
    Exit;

  result := '';
  if TCompilerVersions.ToBdsVersion(compiler) <> '' then
  begin
    key := 'Software\Embarcadero\BDS\' + TCompilerVersions.ToBdsVersion(compiler);
    registry := TRegistry.Create(KEY_READ);
    try
      // the IDE records its install under HKCU, not HKLM
      registry.RootKey := HKEY_CURRENT_USER;
      if registry.OpenKeyReadOnly(key) then
        result := registry.ReadString('RootDir');
    finally
      registry.Free;
    end;
  end;

  if result <> '' then
    result := IncludeTrailingPathDelimiter(result);
  FRootDirs[Ord(compiler)] := result;
end;

function TDelphiEnvironment.IsInstalled(const compiler : TCompilerVersion) : boolean;
var
  root : string;
begin
  root := GetRootDir(compiler);
  result := (root <> '') and TDirectory.Exists(root);
end;

function TDelphiEnvironment.NewestInstalled : TCompilerVersion;
var
  compiler : TCompilerVersion;
begin
  result := cvUnknown;
  for compiler := High(TCompilerVersion) downto Succ(cvUnknown) do
    if IsInstalled(compiler) then
      Exit(compiler);
end;

function TDelphiEnvironment.GetLibraryPath(const compiler : TCompilerVersion;
  const targetPlatform : TDelphiPlatform) : IReadOnlyList<string>;
var
  paths : IList<string>;
  registry : TRegistry;
  key : string;
  raw : string;
  entry : string;
  expanded : string;
begin
  paths := TCollections.CreateList<string>;
  result := paths.AsReadOnly;

  if (TCompilerVersions.ToBdsVersion(compiler) = '') or (TDelphiPlatforms.ToName(targetPlatform) = '') then
    Exit;

  // the value name really does have a space in it
  key := Format('Software\Embarcadero\BDS\%s\Library\%s',
    [TCompilerVersions.ToBdsVersion(compiler), TDelphiPlatforms.ToName(targetPlatform)]);

  registry := TRegistry.Create(KEY_READ);
  try
    registry.RootKey := HKEY_CURRENT_USER;
    if not registry.OpenKeyReadOnly(key) then
      Exit;
    raw := registry.ReadString('Search Path');
  finally
    registry.Free;
  end;

  for entry in raw.Split([';']) do
  begin
    expanded := TBdsTokens.Expand(Trim(entry), GetRootDir(compiler),
      TCompilerVersions.ToBdsVersion(compiler), TDelphiPlatforms.ToName(targetPlatform));
    expanded := ExcludeTrailingPathDelimiter(Trim(expanded));
    if (expanded <> '') and not paths.Contains(expanded) then
      paths.Add(expanded);
  end;
end;

function TDelphiEnvironment.GetSourceFolders(const compiler : TCompilerVersion) : IReadOnlyList<string>;
var
  folders : IList<string>;
  sourceRoot : string;
  folder : string;
begin
  if FSourceFolders.TryGetValue(Ord(compiler), result) then
    Exit;

  folders := TCollections.CreateList<string>;
  result := folders.AsReadOnly;
  FSourceFolders[Ord(compiler)] := result;

  sourceRoot := GetRootDir(compiler);
  if sourceRoot = '' then
    Exit;
  sourceRoot := sourceRoot + 'source';
  if not TDirectory.Exists(sourceRoot) then
    Exit;

  // the rtl and vcl sources are nested several levels deep, so take every folder
  folders.Add(sourceRoot);
  for folder in TDirectory.GetDirectories(sourceRoot, '*', TSearchOption.soAllDirectories) do
    folders.Add(ExcludeTrailingPathDelimiter(folder));
end;

end.
