unit DUA.Tests.DProj;

interface

uses
  DUnitX.TestFramework,
  DUA.Project.MSBuild,
  DUA.Project.DProj;

type
  /// <summary>
  ///   Reading a dproj is mostly about getting the config inheritance right. The XML in
  ///   these tests is the shape the IDE and dpm actually write, trimmed of the noise
  ///   that does not affect property evaluation.
  /// </summary>
  [TestFixture]
  TDProjReaderTests = class
  private
    function Read(const xml : string) : IProjectInfo;
    function ReadSample : IProjectInfo;
    function PropertyFor(const config : string; const platform : string; const name : string) : string;
  public
    // --- structure ---
    [Test] procedure ReadsTheDefaultConfig;
    [Test] procedure ReadsTheDefaultPlatform;
    [Test] procedure ReadsTheConfigNames;
    [Test] procedure ReadsOnlyTheEnabledPlatforms;
    [Test] procedure ReadsTheMainSource;
    [Test] procedure ReadsTheProjectVersion;
    [Test] procedure ReadsTheAppType;
    [Test] procedure ReadsTheDpmCompiler;
    [Test] procedure ResolvesSourceFilesToAbsolutePaths;
    [Test] procedure IncludesTheMainSourceInTheSourceFiles;

    // --- config inheritance ---
    [Test] procedure BasePropertyIsVisibleFromEveryConfig;
    [Test] procedure ConfigPropertyOverridesBase;
    [Test] procedure DebugConfigDefinesDebug;
    [Test] procedure ReleaseConfigDefinesRelease;
    [Test] procedure ReleaseConfigDoesNotDefineDebug;
    [Test] procedure PlatformGroupPrependsToTheBaseValue;
    [Test] procedure Win64GetsADifferentNamespaceListToWin32;
    [Test] procedure PropertyFromAnotherPlatformIsNotApplied;

    // --- dpm ---
    [Test] procedure DpmSearchAppliesOnlyToItsOwnPlatform;
    [Test] procedure UnitSearchPathContainsTheExpandedDpmPath;

    [Test] procedure ResolvesAPropertyDefinedAfterTheOneThatUsesIt;

    // --- errors ---
    [Test] procedure MalformedXmlRaises;
    [Test] procedure MissingFileRaises;
  end;

implementation

uses
  System.IOUtils,
  System.SysUtils;

const
  // A cut down but structurally faithful Delphi 13 console dproj with two configs, two
  // platforms and a dpm package installed.
  SampleDProj =
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '  <PropertyGroup>' +
    '    <ProjectGuid>{55FA8C89-B539-4888-A7C5-08FEDBB01243}</ProjectGuid>' +
    '    <MainSource>MyApp.dpr</MainSource>' +
    '    <Base>True</Base>' +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>' +
    '    <AppType>Console</AppType>' +
    '    <FrameworkType>None</FrameworkType>' +
    '    <ProjectVersion>20.4</ProjectVersion>' +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup>' +
    '    <DPMCompiler>delphi13.0</DPMCompiler>' +
    '    <DPMCache Condition="''$(DPMCache)'' == ''''">C:\cache</DPMCache>' +
    '    <DPM>$(DPMCache)\$(DPMCompiler)</DPM>' +
    '    <DPMSearch Condition="''$(Platform)''==''Win32''">$(DPM)\VSoft.YAML\1.7.1\lib\Win32;</DPMSearch>' +
    '    <DPMSearch Condition="''$(Platform)''==''Win64''">$(DPM)\VSoft.YAML\1.7.1\lib\Win64;</DPMSearch>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="''$(Config)''==''Base'' or ''$(Base)''!=''''">' +
    '    <Base>true</Base>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="(''$(Platform)''==''Win32'' and ''$(Base)''==''true'') or ''$(Base_Win32)''!=''''">' +
    '    <Base_Win32>true</Base_Win32>' +
    '    <CfgParent>Base</CfgParent>' +
    '    <Base>true</Base>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="(''$(Platform)''==''Win64'' and ''$(Base)''==''true'') or ''$(Base_Win64)''!=''''">' +
    '    <Base_Win64>true</Base_Win64>' +
    '    <CfgParent>Base</CfgParent>' +
    '    <Base>true</Base>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="''$(Config)''==''Release'' or ''$(Cfg_1)''!=''''">' +
    '    <Cfg_1>true</Cfg_1>' +
    '    <CfgParent>Base</CfgParent>' +
    '    <Base>true</Base>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="''$(Config)''==''Debug'' or ''$(Cfg_2)''!=''''">' +
    '    <Cfg_2>true</Cfg_2>' +
    '    <CfgParent>Base</CfgParent>' +
    '    <Base>true</Base>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' +
    '    <DCC_Namespace>System;Xml;Data;Datasnap;Web;Soap;$(DCC_Namespace)</DCC_Namespace>' +
    '    <DCC_UnitSearchPath>$(DPMSearch);$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' +
    '    <DCC_ExeOutput>..\Output</DCC_ExeOutput>' +
    '    <SharedSetting>from-base</SharedSetting>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="''$(Base_Win32)''!=''''">' +
    '    <DCC_Namespace>Winapi;System.Win;Data.Win;Bde;$(DCC_Namespace)</DCC_Namespace>' +
    '    <Win32Only>yes</Win32Only>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="''$(Base_Win64)''!=''''">' +
    '    <DCC_Namespace>Winapi;System.Win;Data.Win;$(DCC_Namespace)</DCC_Namespace>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="''$(Cfg_1)''!=''''">' +
    '    <DCC_Define>RELEASE;$(DCC_Define)</DCC_Define>' +
    '    <SharedSetting>from-release</SharedSetting>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="''$(Cfg_2)''!=''''">' +
    '    <DCC_Define>DEBUG;$(DCC_Define)</DCC_Define>' +
    '    <SharedSetting>from-debug</SharedSetting>' +
    '  </PropertyGroup>' +
    '  <ItemGroup>' +
    '    <DelphiCompile Include="$(MainSource)">' +
    '      <MainSource>MainSource</MainSource>' +
    '    </DelphiCompile>' +
    '    <DCCReference Include="MyUnit.pas"/>' +
    '    <DCCReference Include="..\Shared\Helpers.pas"/>' +
    '    <BuildConfiguration Include="Base">' +
    '      <Key>Base</Key>' +
    '    </BuildConfiguration>' +
    '    <BuildConfiguration Include="Release">' +
    '      <Key>Cfg_1</Key>' +
    '      <CfgParent>Base</CfgParent>' +
    '    </BuildConfiguration>' +
    '    <BuildConfiguration Include="Debug">' +
    '      <Key>Cfg_2</Key>' +
    '      <CfgParent>Base</CfgParent>' +
    '    </BuildConfiguration>' +
    '  </ItemGroup>' +
    '  <ProjectExtensions>' +
    '    <BorlandProject>' +
    '      <Platforms>' +
    '        <Platform value="Linux64">False</Platform>' +
    '        <Platform value="Win32">True</Platform>' +
    '        <Platform value="Win64">True</Platform>' +
    '      </Platforms>' +
    '    </BorlandProject>' +
    '  </ProjectExtensions>' +
    '</Project>';

  SampleProjectFile = 'C:\src\MyApp\MyApp.dproj';

{ TDProjReaderTests }

function TDProjReaderTests.Read(const xml : string) : IProjectInfo;
var
  reader : IDProjReader;
begin
  reader := TDProjReader.Create;
  result := reader.ReadText(xml, SampleProjectFile);
end;

function TDProjReaderTests.ReadSample : IProjectInfo;
begin
  result := Read(SampleDProj);
end;

function TDProjReaderTests.PropertyFor(const config : string; const platform : string;
  const name : string) : string;
begin
  result := ReadSample.GetProperties(config, platform).GetValue(name);
end;

procedure TDProjReaderTests.ReadsTheDefaultConfig;
begin
  Assert.AreEqual('Debug', ReadSample.DefaultConfig);
end;

procedure TDProjReaderTests.ReadsTheDefaultPlatform;
begin
  Assert.AreEqual('Win32', ReadSample.DefaultPlatform);
end;

procedure TDProjReaderTests.ReadsTheConfigNames;
var
  info : IProjectInfo;
begin
  info := ReadSample;
  Assert.AreEqual<integer>(3, info.ConfigNames.Count);
  Assert.IsTrue(info.ConfigNames.Contains('Base'), 'Base');
  Assert.IsTrue(info.ConfigNames.Contains('Debug'), 'Debug');
  Assert.IsTrue(info.ConfigNames.Contains('Release'), 'Release');
end;

procedure TDProjReaderTests.ReadsOnlyTheEnabledPlatforms;
var
  info : IProjectInfo;
begin
  info := ReadSample;
  Assert.AreEqual<integer>(2, info.PlatformNames.Count, 'Linux64 is False and must not be listed');
  Assert.IsTrue(info.PlatformNames.Contains('Win32'), 'Win32');
  Assert.IsTrue(info.PlatformNames.Contains('Win64'), 'Win64');
end;

procedure TDProjReaderTests.ReadsTheMainSource;
begin
  Assert.AreEqual('C:\src\MyApp\MyApp.dpr', ReadSample.MainSource);
end;

procedure TDProjReaderTests.ReadsTheProjectVersion;
begin
  Assert.AreEqual('20.4', ReadSample.ProjectVersion);
end;

procedure TDProjReaderTests.ReadsTheAppType;
begin
  Assert.AreEqual('Console', ReadSample.AppType);
end;

procedure TDProjReaderTests.ReadsTheDpmCompiler;
begin
  Assert.AreEqual('delphi13.0', ReadSample.DpmCompiler);
end;

procedure TDProjReaderTests.ResolvesSourceFilesToAbsolutePaths;
var
  info : IProjectInfo;
begin
  info := ReadSample;
  Assert.IsTrue(info.SourceFiles.Contains('C:\src\MyApp\MyUnit.pas'), 'MyUnit.pas');
  Assert.IsTrue(info.SourceFiles.Contains('C:\src\Shared\Helpers.pas'),
    'the ..\ in the reference should be collapsed');
end;

procedure TDProjReaderTests.IncludesTheMainSourceInTheSourceFiles;
begin
  // DelphiCompile Include is $(MainSource), so it has to be expanded like any property
  Assert.IsTrue(ReadSample.SourceFiles.Contains('C:\src\MyApp\MyApp.dpr'));
end;

procedure TDProjReaderTests.BasePropertyIsVisibleFromEveryConfig;
begin
  Assert.AreEqual('..\Output', PropertyFor('Debug', 'Win32', 'DCC_ExeOutput'));
  Assert.AreEqual('..\Output', PropertyFor('Release', 'Win64', 'DCC_ExeOutput'));
end;

procedure TDProjReaderTests.ConfigPropertyOverridesBase;
begin
  Assert.AreEqual('from-debug', PropertyFor('Debug', 'Win32', 'SharedSetting'));
  Assert.AreEqual('from-release', PropertyFor('Release', 'Win32', 'SharedSetting'));
end;

procedure TDProjReaderTests.DebugConfigDefinesDebug;
begin
  Assert.StartsWith('DEBUG', PropertyFor('Debug', 'Win32', 'DCC_Define'));
end;

procedure TDProjReaderTests.ReleaseConfigDefinesRelease;
begin
  Assert.StartsWith('RELEASE', PropertyFor('Release', 'Win32', 'DCC_Define'));
end;

procedure TDProjReaderTests.ReleaseConfigDoesNotDefineDebug;
begin
  Assert.DoesNotContain(PropertyFor('Release', 'Win32', 'DCC_Define'), 'DEBUG');
end;

procedure TDProjReaderTests.PlatformGroupPrependsToTheBaseValue;
var
  namespaces : string;
begin
  namespaces := PropertyFor('Debug', 'Win32', 'DCC_Namespace');

  // the Win32 group prepends its own scopes to whatever Base set, via $(DCC_Namespace)
  Assert.StartsWith('Winapi;', namespaces);
  Assert.Contains(namespaces, 'System;Xml;Data', 'the base list must survive');
end;

procedure TDProjReaderTests.Win64GetsADifferentNamespaceListToWin32;
begin
  Assert.Contains(PropertyFor('Debug', 'Win32', 'DCC_Namespace'), 'Bde');
  Assert.DoesNotContain(PropertyFor('Debug', 'Win64', 'DCC_Namespace'), 'Bde');
end;

procedure TDProjReaderTests.PropertyFromAnotherPlatformIsNotApplied;
begin
  Assert.AreEqual('yes', PropertyFor('Debug', 'Win32', 'Win32Only'));
  Assert.AreEqual('', PropertyFor('Debug', 'Win64', 'Win32Only'),
    'a Win32 only property leaked into the Win64 evaluation');
end;

procedure TDProjReaderTests.DpmSearchAppliesOnlyToItsOwnPlatform;
begin
  Assert.Contains(PropertyFor('Debug', 'Win32', 'DPMSearch'), 'lib\Win32');
  Assert.Contains(PropertyFor('Debug', 'Win64', 'DPMSearch'), 'lib\Win64');
end;

procedure TDProjReaderTests.UnitSearchPathContainsTheExpandedDpmPath;
begin
  // this is what makes units from a dpm package resolvable
  Assert.Contains(PropertyFor('Debug', 'Win32', 'DCC_UnitSearchPath'),
    'C:\cache\delphi13.0\VSoft.YAML\1.7.1\lib\Win32');
end;

procedure TDProjReaderTests.ResolvesAPropertyDefinedAfterTheOneThatUsesIt;
var
  info : IProjectInfo;
begin
  // dpm appends its DPMSearch group near the end of the file, well after the Base group
  // that consumes it. Strict document order would leave the search path empty and every
  // package unit unresolved, so a later definition still has to be picked up.
  info := Read(
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">' +
    '  <PropertyGroup>' +
    '    <Base>True</Base>' +
    '    <Config Condition="''$(Config)''==''''">Debug</Config>' +
    '    <Platform Condition="''$(Platform)''==''''">Win32</Platform>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup Condition="''$(Base)''!=''''">' +
    '    <DCC_UnitSearchPath>$(DPMSearch);$(DCC_UnitSearchPath)</DCC_UnitSearchPath>' +
    '  </PropertyGroup>' +
    '  <PropertyGroup>' +
    '    <DPMSearch Condition="''$(Platform)''==''Win32''">C:\cache\SomePackage\lib\Win32;</DPMSearch>' +
    '  </PropertyGroup>' +
    '</Project>');

  Assert.Contains(info.GetProperties('Debug', 'Win32').GetValue('DCC_UnitSearchPath'),
    'C:\cache\SomePackage\lib\Win32');
end;

procedure TDProjReaderTests.MalformedXmlRaises;
begin
  Assert.WillRaise(
    procedure
    begin
      Read('<Project><PropertyGroup></Project>');
    end, EDProjReadError);
end;

procedure TDProjReaderTests.MissingFileRaises;
var
  reader : IDProjReader;
begin
  reader := TDProjReader.Create;
  Assert.WillRaise(
    procedure
    begin
      reader.ReadFile(TPath.Combine(TPath.GetTempPath, 'no-such-project-xyzzy.dproj'));
    end, EDProjReadError);
end;

initialization
  TDUnitX.RegisterTestFixture(TDProjReaderTests);

end.
