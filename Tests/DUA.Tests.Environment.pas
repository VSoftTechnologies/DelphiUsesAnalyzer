unit DUA.Tests.Environment;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>
  ///   The IDE stores its library path unexpanded, so without this every entry is a
  ///   folder that does not exist. On a real machine the Win32 library path reads
  ///   "$(BDSLIB)\$(Platform)\release;$(BDSUSERDIR)\Imports;...".
  /// </summary>
  [TestFixture]
  TBdsTokenTests = class
  private
    const RootDir = 'E:\emb\Studio\37.0\';
    const BdsVersion = '37.0';
    function Expand(const value : string) : string;
    function ExpandFor(const value : string; const platformName : string) : string;
  public
    [Test] procedure EmptyStringStaysEmpty;
    [Test] procedure TextWithNoTokensIsUnchanged;

    [Test] procedure BdsBecomesTheRootWithoutATrailingSlash;
    [Test] procedure BdsLibIsTheLibFolder;
    [Test] procedure BdsBinIsTheBinFolder;
    [Test] procedure BdsIncludeIsTheIncludeFolder;

    [Test] procedure BdsLibIsNotEatenByBds;
    [Test] procedure BdsCommonDirIsNotEatenByBds;

    [Test] procedure BdsUserDirIsUnderTheUserDocuments;
    [Test] procedure BdsCommonDirIsUnderThePublicDocuments;
    [Test] procedure BdsProjectsDirIsUnderTheUserDocuments;
    [Test] procedure BdsCatalogRepositoryIsUnderTheUserDocuments;

    [Test] procedure PlatformTokenIsReplaced;
    [Test] procedure TokensAreCaseInsensitive;
    [Test] procedure EnvironmentVariablesAreExpanded;
    [Test] procedure ExpandsARealLibraryPathEntry;
    [Test] procedure RootDirWithoutATrailingSlashWorksToo;
  end;

  /// <summary>
  ///   These touch the real registry. They assert only what must hold on any machine,
  ///   so they stay green whether or not a particular Delphi is installed.
  /// </summary>
  [TestFixture]
  TDelphiEnvironmentTests = class
  public
    [Test] procedure AnUninstallableCompilerHasNoRootDir;
    [Test] procedure RootDirOfAnInstalledCompilerEndsWithADelimiter;
    [Test] procedure NewestInstalledIsActuallyInstalled;
    [Test] procedure LibraryPathEntriesAreFullyExpanded;
    [Test] procedure SourceFoldersIncludeTheRtl;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  System.SysUtils,
  Winapi.Windows,
  Spring.Collections,
  DUA.Compiler.Versions,
  DUA.Compiler.Environment;

{ TBdsTokenTests }

function TBdsTokenTests.Expand(const value : string) : string;
begin
  result := ExpandFor(value, 'Win32');
end;

function TBdsTokenTests.ExpandFor(const value : string; const platformName : string) : string;
begin
  result := TBdsTokens.Expand(value, RootDir, BdsVersion, platformName);
end;

procedure TBdsTokenTests.EmptyStringStaysEmpty;
begin
  Assert.AreEqual('', Expand(''));
end;

procedure TBdsTokenTests.TextWithNoTokensIsUnchanged;
begin
  Assert.AreEqual('C:\some\ordinary\path', Expand('C:\some\ordinary\path'));
end;

procedure TBdsTokenTests.BdsBecomesTheRootWithoutATrailingSlash;
begin
  Assert.AreEqual('E:\emb\Studio\37.0', Expand('$(BDS)'));
end;

procedure TBdsTokenTests.BdsLibIsTheLibFolder;
begin
  Assert.AreEqual('E:\emb\Studio\37.0\lib', Expand('$(BDSLIB)'));
end;

procedure TBdsTokenTests.BdsBinIsTheBinFolder;
begin
  Assert.AreEqual('E:\emb\Studio\37.0\bin', Expand('$(BDSBIN)'));
end;

procedure TBdsTokenTests.BdsIncludeIsTheIncludeFolder;
begin
  Assert.AreEqual('E:\emb\Studio\37.0\include', Expand('$(BDSINCLUDE)'));
end;

procedure TBdsTokenTests.BdsLibIsNotEatenByBds;
begin
  // replacing $(BDS) first would turn $(BDSLIB) into "<root>LIB)"
  Assert.AreEqual('E:\emb\Studio\37.0\lib\Win32\release', Expand('$(BDSLIB)\$(Platform)\release'));
end;

procedure TBdsTokenTests.BdsCommonDirIsNotEatenByBds;
begin
  Assert.DoesNotContain(Expand('$(BDSCOMMONDIR)'), 'COMMONDIR',
    'a longer token was chewed up by a shorter one');
end;

procedure TBdsTokenTests.BdsUserDirIsUnderTheUserDocuments;
begin
  Assert.AreEqual(
    GetEnvironmentVariable('USERPROFILE') + '\Documents\Embarcadero\Studio\37.0',
    Expand('$(BDSUSERDIR)'));
end;

procedure TBdsTokenTests.BdsCommonDirIsUnderThePublicDocuments;
begin
  Assert.AreEqual(
    GetEnvironmentVariable('PUBLIC') + '\Documents\Embarcadero\Studio\37.0',
    Expand('$(BDSCOMMONDIR)'));
end;

procedure TBdsTokenTests.BdsProjectsDirIsUnderTheUserDocuments;
begin
  Assert.AreEqual(
    GetEnvironmentVariable('USERPROFILE') + '\Documents\Embarcadero\Studio\37.0\Projects',
    Expand('$(BDSPROJECTSDIR)'));
end;

procedure TBdsTokenTests.BdsCatalogRepositoryIsUnderTheUserDocuments;
begin
  // this one appears in real library paths for GetIt installed packages
  Assert.AreEqual(
    GetEnvironmentVariable('USERPROFILE') + '\Documents\Embarcadero\Studio\37.0\CatalogRepository',
    Expand('$(BDSCatalogRepository)'));
end;

procedure TBdsTokenTests.PlatformTokenIsReplaced;
begin
  Assert.AreEqual('E:\emb\Studio\37.0\lib\Win64', ExpandFor('$(BDSLIB)\$(Platform)', 'Win64'));
end;

procedure TBdsTokenTests.TokensAreCaseInsensitive;
begin
  Assert.AreEqual('E:\emb\Studio\37.0\lib', Expand('$(bdslib)'));
  Assert.AreEqual('E:\emb\Studio\37.0\lib', Expand('$(BdsLib)'));
end;

procedure TBdsTokenTests.EnvironmentVariablesAreExpanded;
begin
  SetEnvironmentVariable('DUA_ENV_TEST', 'expanded-value');
  try
    Assert.AreEqual('x-expanded-value-y', Expand('x-%DUA_ENV_TEST%-y'));
  finally
    SetEnvironmentVariable('DUA_ENV_TEST', nil);
  end;
end;

procedure TBdsTokenTests.ExpandsARealLibraryPathEntry;
var
  expanded : string;
begin
  // taken verbatim from a real HKCU BDS Library Search Path
  expanded := Expand('$(BDSLIB)\$(Platform)\release;$(BDSUSERDIR)\Imports;$(BDS)\include');

  Assert.Contains(expanded, 'E:\emb\Studio\37.0\lib\Win32\release');
  Assert.Contains(expanded, '\Documents\Embarcadero\Studio\37.0\Imports');
  Assert.Contains(expanded, 'E:\emb\Studio\37.0\include');
  Assert.DoesNotContain(expanded, '$(', 'something was left unexpanded');
end;

procedure TBdsTokenTests.RootDirWithoutATrailingSlashWorksToo;
begin
  Assert.AreEqual('E:\emb\Studio\37.0\lib',
    TBdsTokens.Expand('$(BDSLIB)', 'E:\emb\Studio\37.0', '37.0', 'Win32'));
end;

{ TDelphiEnvironmentTests }

procedure TDelphiEnvironmentTests.AnUninstallableCompilerHasNoRootDir;
var
  environment : IDelphiEnvironment;
begin
  environment := TDelphiEnvironment.Create;
  Assert.AreEqual('', environment.GetRootDir(cvUnknown));
  Assert.IsFalse(environment.IsInstalled(cvUnknown));
end;

procedure TDelphiEnvironmentTests.RootDirOfAnInstalledCompilerEndsWithADelimiter;
var
  environment : IDelphiEnvironment;
  compiler : TCompilerVersion;
  root : string;
begin
  environment := TDelphiEnvironment.Create;
  for compiler := Succ(cvUnknown) to High(TCompilerVersion) do
  begin
    root := environment.GetRootDir(compiler);
    if root = '' then
      Continue;
    Assert.EndsWith(PathDelim, root, TCompilerVersions.ToDisplayName(compiler));
  end;
  Assert.Pass('checked every installed compiler');
end;

procedure TDelphiEnvironmentTests.NewestInstalledIsActuallyInstalled;
var
  environment : IDelphiEnvironment;
  newest : TCompilerVersion;
begin
  environment := TDelphiEnvironment.Create;
  newest := environment.NewestInstalled;
  if newest = cvUnknown then
    Assert.Pass('no Delphi installed on this machine');

  Assert.IsTrue(environment.IsInstalled(newest),
    TCompilerVersions.ToDisplayName(newest) + ' was reported as newest but is not installed');
  Assert.IsTrue(TDirectory.Exists(environment.GetRootDir(newest)));
end;

procedure TDelphiEnvironmentTests.LibraryPathEntriesAreFullyExpanded;
var
  environment : IDelphiEnvironment;
  newest : TCompilerVersion;
  entry : string;
begin
  environment := TDelphiEnvironment.Create;
  newest := environment.NewestInstalled;
  if newest = cvUnknown then
    Assert.Pass('no Delphi installed on this machine');

  for entry in environment.GetLibraryPath(newest, dpWin32) do
  begin
    Assert.DoesNotContain(entry, '$(', 'unexpanded token in: ' + entry);
    Assert.DoesNotContain(entry, '%', 'unexpanded environment variable in: ' + entry);
  end;
  Assert.Pass('every entry expanded');
end;

procedure TDelphiEnvironmentTests.SourceFoldersIncludeTheRtl;
var
  environment : IDelphiEnvironment;
  newest : TCompilerVersion;
  folders : IReadOnlyList<string>;
  folder : string;
  foundRtl : boolean;
begin
  environment := TDelphiEnvironment.Create;
  newest := environment.NewestInstalled;
  if newest = cvUnknown then
    Assert.Pass('no Delphi installed on this machine');

  folders := environment.GetSourceFolders(newest);
  if folders.Count = 0 then
    Assert.Pass('this installation has no source folder');

  foundRtl := false;
  for folder in folders do
    if ContainsText(folder, '\source\rtl') then
      foundRtl := true;

  Assert.IsTrue(foundRtl, 'the rtl source folder should be found, so System.Classes resolves');
end;

initialization
  TDUnitX.RegisterTestFixture(TBdsTokenTests);
  TDUnitX.RegisterTestFixture(TDelphiEnvironmentTests);

end.
