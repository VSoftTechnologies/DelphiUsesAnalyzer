unit DUA.Project.DProj;

interface

uses
  System.SysUtils,
  Spring.Collections,
  DUA.Project.MSBuild;

type
  EDProjReadError = class(Exception);

  IProjectInfo = interface
    ['{7E2D4B91-6C05-4A38-9F1B-3D8A05C2E764}']
    function GetProjectFile : string;
    function GetProjectDir : string;
    function GetConfigNames : IReadOnlyList<string>;
    function GetPlatformNames : IReadOnlyList<string>;
    function GetDefaultConfig : string;
    function GetDefaultPlatform : string;
    /// <summary>Absolute paths of every DCCReference and DelphiCompile entry.</summary>
    function GetSourceFiles : IReadOnlyList<string>;

    /// <summary>
    ///   Every property in effect for this config and platform, evaluated the way
    ///   msbuild would: groups in document order, conditions honoured, and $(Name)
    ///   references expanded as each value is set.
    /// </summary>
    function GetProperties(const config : string; const platform : string) : IMSBuildProperties;

    // convenience readers, evaluated against the default config and platform
    function GetMainSource : string;
    function GetProjectVersion : string;
    function GetAppType : string;
    function GetDpmCompiler : string;

    property ProjectFile : string read GetProjectFile;
    property ProjectDir : string read GetProjectDir;
    property ConfigNames : IReadOnlyList<string> read GetConfigNames;
    property PlatformNames : IReadOnlyList<string> read GetPlatformNames;
    property DefaultConfig : string read GetDefaultConfig;
    property DefaultPlatform : string read GetDefaultPlatform;
    property SourceFiles : IReadOnlyList<string> read GetSourceFiles;
    property MainSource : string read GetMainSource;
    property ProjectVersion : string read GetProjectVersion;
    property AppType : string read GetAppType;
    property DpmCompiler : string read GetDpmCompiler;
  end;

  IDProjReader = interface
    ['{0A5C8E13-4F27-4B6D-8E90-1C7B3A2D5F48}']
    function ReadFile(const fileName : string) : IProjectInfo;
    /// <summary>fileName is only used to resolve relative paths, the file is not read.</summary>
    function ReadText(const xml : string; const fileName : string) : IProjectInfo;
  end;

  TDProjReader = class(TInterfacedObject, IDProjReader)
  protected
    function ReadFile(const fileName : string) : IProjectInfo;
    function ReadText(const xml : string; const fileName : string) : IProjectInfo;
  end;

implementation

uses
  System.IOUtils,
  System.Variants,
  Winapi.ActiveX,
  Winapi.msxml;

type
  /// <summary>One element inside a PropertyGroup, with its own optional Condition.</summary>
  TPropertyDefinition = class
  public
    Name : string;
    Condition : string;
    Value : string;
  end;

  TPropertyGroupDefinition = class
  public
    Condition : string;
    Items : IList<TPropertyDefinition>;
    constructor Create;
  end;

  TProjectInfo = class(TInterfacedObject, IProjectInfo)
  private
    FProjectFile : string;
    FProjectDir : string;
    FGroups : IList<TPropertyGroupDefinition>;
    FConfigNames : IList<string>;
    FPlatformNames : IList<string>;
    FRawSourceFiles : IList<string>;
    FDefaultConfig : string;
    FDefaultPlatform : string;
    FSourceFiles : IList<string>;
    FPropertyCache : IDictionary<string, IMSBuildProperties>;
    function DefaultProperties : IMSBuildProperties;
    function ToAbsolute(const value : string) : string;
    procedure ApplyGroup(const group : TObject; const properties : IMSBuildProperties);
    procedure ResolveForwardReferences(const properties : IMSBuildProperties);
  protected
    function GetProjectFile : string;
    function GetProjectDir : string;
    function GetConfigNames : IReadOnlyList<string>;
    function GetPlatformNames : IReadOnlyList<string>;
    function GetDefaultConfig : string;
    function GetDefaultPlatform : string;
    function GetSourceFiles : IReadOnlyList<string>;
    function GetProperties(const config : string; const platform : string) : IMSBuildProperties;
    function GetMainSource : string;
    function GetProjectVersion : string;
    function GetAppType : string;
    function GetDpmCompiler : string;
  public
    constructor Create(const fileName : string);
    procedure Load(const xml : string);
  end;

{ TPropertyGroupDefinition }

constructor TPropertyGroupDefinition.Create;
begin
  inherited Create;
  Items := TCollections.CreateObjectList<TPropertyDefinition>(true);
end;

{ helpers }

function AttributeValue(const node : IXMLDOMNode; const name : string) : string;
var
  attribute : IXMLDOMNode;
begin
  result := '';
  if (node = nil) or (node.attributes = nil) then
    Exit;
  attribute := node.attributes.getNamedItem(name);
  if attribute <> nil then
    result := VarToStr(attribute.nodeValue);
end;

/// <summary>
///   Element name without any namespace prefix. Walking the DOM by name rather than by
///   XPath sidesteps the namespace registration a dproj's default xmlns would otherwise
///   force on every single query.
/// </summary>
function ElementName(const node : IXMLDOMNode) : string;
begin
  if node = nil then
    result := ''
  else
    result := node.baseName;
end;

function FindChild(const node : IXMLDOMNode; const name : string) : IXMLDOMNode;
var
  index : integer;
begin
  result := nil;
  if node = nil then
    Exit;
  for index := 0 to node.childNodes.length - 1 do
    if SameText(ElementName(node.childNodes[index]), name) then
      Exit(node.childNodes[index]);
end;

{ TProjectInfo }

constructor TProjectInfo.Create(const fileName : string);
begin
  inherited Create;
  FProjectFile := fileName;
  FProjectDir := IncludeTrailingPathDelimiter(ExtractFilePath(fileName));
  FGroups := TCollections.CreateObjectList<TPropertyGroupDefinition>(true);
  FConfigNames := TCollections.CreateList<string>;
  FPlatformNames := TCollections.CreateList<string>;
  FRawSourceFiles := TCollections.CreateList<string>;
  FPropertyCache := TCollections.CreateDictionary<string, IMSBuildProperties>;
end;

procedure TProjectInfo.Load(const xml : string);
var
  document : IXMLDOMDocument3;
  root : IXMLDOMNode;
  node : IXMLDOMNode;
  child : IXMLDOMNode;
  platformsNode : IXMLDOMNode;
  group : TPropertyGroupDefinition;
  definition : TPropertyDefinition;
  outer : integer;
  inner : integer;
  include : string;
begin
  document := CoDOMDocument60.Create;
  document.async := false;
  document.validateOnParse := false;
  document.resolveExternals := false;

  if not document.loadXML(xml) then
    raise EDProjReadError.CreateFmt('%s is not valid xml: %s (line %d)',
      [FProjectFile, Trim(document.parseError.reason), document.parseError.line]);

  root := document.documentElement;
  if (root = nil) or not SameText(ElementName(root), 'Project') then
    raise EDProjReadError.CreateFmt('%s does not look like a dproj, the root element is <%s>',
      [FProjectFile, ElementName(root)]);

  for outer := 0 to root.childNodes.length - 1 do
  begin
    node := root.childNodes[outer];

    if SameText(ElementName(node), 'PropertyGroup') then
    begin
      group := TPropertyGroupDefinition.Create;
      FGroups.Add(group);
      group.Condition := AttributeValue(node, 'Condition');
      for inner := 0 to node.childNodes.length - 1 do
      begin
        child := node.childNodes[inner];
        if child.nodeType <> NODE_ELEMENT then
          Continue;
        definition := TPropertyDefinition.Create;
        group.Items.Add(definition);
        definition.Name := ElementName(child);
        definition.Condition := AttributeValue(child, 'Condition');
        definition.Value := child.text;
      end;
      Continue;
    end;

    if SameText(ElementName(node), 'ItemGroup') then
    begin
      for inner := 0 to node.childNodes.length - 1 do
      begin
        child := node.childNodes[inner];
        include := AttributeValue(child, 'Include');
        if include = '' then
          Continue;

        if SameText(ElementName(child), 'BuildConfiguration') then
          FConfigNames.Add(include)
        else if SameText(ElementName(child), 'DCCReference') or
                SameText(ElementName(child), 'DelphiCompile') then
          FRawSourceFiles.Add(include);
      end;
      Continue;
    end;

    if SameText(ElementName(node), 'ProjectExtensions') then
    begin
      platformsNode := FindChild(FindChild(node, 'BorlandProject'), 'Platforms');
      if platformsNode = nil then
        Continue;
      for inner := 0 to platformsNode.childNodes.length - 1 do
      begin
        child := platformsNode.childNodes[inner];
        if not SameText(ElementName(child), 'Platform') then
          Continue;
        // a platform the project does not target is listed with False
        if SameText(Trim(child.text), 'True') then
          FPlatformNames.Add(AttributeValue(child, 'value'));
      end;
    end;
  end;

  // The defaults are what msbuild uses when invoked without /p:Config or /p:Platform,
  // written as a condition on the property itself.
  for group in FGroups do
    for definition in group.Items do
    begin
      if SameText(definition.Name, 'Config') and (FDefaultConfig = '') and
         (Pos('$(Config)', definition.Condition) > 0) then
        FDefaultConfig := Trim(definition.Value);
      if SameText(definition.Name, 'Platform') and (FDefaultPlatform = '') and
         (Pos('$(Platform)', definition.Condition) > 0) then
        FDefaultPlatform := Trim(definition.Value);
    end;

  if FDefaultConfig = '' then
    FDefaultConfig := 'Debug';
  if FDefaultPlatform = '' then
  begin
    if FPlatformNames.Count > 0 then
      FDefaultPlatform := FPlatformNames[0]
    else
      FDefaultPlatform := 'Win32';
  end;
end;

function TProjectInfo.GetProperties(const config : string; const platform : string) : IMSBuildProperties;
var
  properties : IMSBuildProperties;
  group : TPropertyGroupDefinition;
  definition : TPropertyDefinition;
  key : string;
begin
  key := UpperCase(config + '|' + platform);
  if FPropertyCache.TryGetValue(key, result) then
    Exit;

  properties := TMSBuildProperties.Create;
  // seed what msbuild is invoked with, plus the project properties the IDE targets
  // supply, so conditions and $(MSBuildProjectName) references resolve
  properties.SetValue('Config', config);
  properties.SetValue('Platform', platform);
  properties.SetValue('MSBuildProjectName', ChangeFileExt(ExtractFileName(FProjectFile), ''));
  properties.SetValue('MSBuildProjectDirectory', ExcludeTrailingPathDelimiter(FProjectDir));
  properties.SetValue('MSBuildProjectFullPath', FProjectFile);

  // A dproj can consume a property that is only defined further down the file: dpm
  // appends its DPMSearch group near the end, well after the Base group whose
  // DCC_UnitSearchPath uses it. Because a value is expanded as it is assigned, strict
  // document order would bake in an empty string there and every unit from a package
  // would go unresolved. Groups with no condition always apply, so seeding those first
  // settles the forward references without changing what any condition means.
  for group in FGroups do
  begin
    if Trim(group.Condition) <> '' then
      Continue;
    ApplyGroup(group, properties);
  end;

  for group in FGroups do
  begin
    if not TMSBuild.EvaluateCondition(group.Condition, properties) then
      Continue;
    ApplyGroup(group, properties);
  end;

  // A dproj can reference a property that is only defined further down the file: dpm
  // appends its DPMSearch group after the Base group that consumes it. Strict document
  // order leaves that empty, and then every unit from a package goes unresolved - so
  // settle the remaining references against the finished set.
  ResolveForwardReferences(properties);

  FPropertyCache[key] := properties;
  result := properties;
end;

procedure TProjectInfo.ApplyGroup(const group : TObject; const properties : IMSBuildProperties);
var
  definition : TPropertyDefinition;
begin
  for definition in TPropertyGroupDefinition(group).Items do
  begin
    if not TMSBuild.EvaluateCondition(definition.Condition, properties) then
      Continue;
    // expanding as we assign is what makes the $(DCC_Namespace) self reference inherit
    // the value the previous group set, rather than looping forever
    properties.SetValue(definition.Name, TMSBuild.Expand(definition.Value, properties));
  end;
end;

procedure TProjectInfo.ResolveForwardReferences(const properties : IMSBuildProperties);
const
  // a property that expands to something still containing a reference needs another
  // go, but a self reference would grow forever, so cap it
  MaxPasses = 3;
var
  pass : integer;
  name : string;
  value : string;
  expanded : string;
  changed : boolean;
begin
  for pass := 1 to MaxPasses do
  begin
    changed := false;
    for name in properties.Names do
    begin
      value := properties.GetValue(name);
      if Pos('$(', value) = 0 then
        Continue;
      expanded := TMSBuild.Expand(value, properties);
      if expanded <> value then
      begin
        properties.SetValue(name, expanded);
        changed := true;
      end;
    end;
    if not changed then
      Break;
  end;
end;

function TProjectInfo.DefaultProperties : IMSBuildProperties;
begin
  result := GetProperties(FDefaultConfig, FDefaultPlatform);
end;

function TProjectInfo.ToAbsolute(const value : string) : string;
begin
  if value = '' then
    Exit('');
  if TPath.IsPathRooted(value) then
    result := TPath.GetFullPath(value)
  else
    // GetFullPath collapses the ..\ a reference to a shared folder uses
    result := TPath.GetFullPath(TPath.Combine(FProjectDir, value));
end;

function TProjectInfo.GetProjectFile : string;
begin
  result := FProjectFile;
end;

function TProjectInfo.GetProjectDir : string;
begin
  result := FProjectDir;
end;

function TProjectInfo.GetConfigNames : IReadOnlyList<string>;
begin
  result := FConfigNames.AsReadOnly;
end;

function TProjectInfo.GetPlatformNames : IReadOnlyList<string>;
begin
  result := FPlatformNames.AsReadOnly;
end;

function TProjectInfo.GetDefaultConfig : string;
begin
  result := FDefaultConfig;
end;

function TProjectInfo.GetDefaultPlatform : string;
begin
  result := FDefaultPlatform;
end;

function TProjectInfo.GetSourceFiles : IReadOnlyList<string>;
var
  raw : string;
  full : string;
begin
  if FSourceFiles = nil then
  begin
    FSourceFiles := TCollections.CreateList<string>;
    for raw in FRawSourceFiles do
    begin
      // DelphiCompile is included as $(MainSource), so an Include needs expanding too
      full := ToAbsolute(TMSBuild.Expand(raw, DefaultProperties));
      if (full <> '') and not FSourceFiles.Contains(full) then
        FSourceFiles.Add(full);
    end;
  end;
  result := FSourceFiles.AsReadOnly;
end;

function TProjectInfo.GetMainSource : string;
begin
  result := ToAbsolute(DefaultProperties.GetValue('MainSource'));
end;

function TProjectInfo.GetProjectVersion : string;
begin
  result := Trim(DefaultProperties.GetValue('ProjectVersion'));
end;

function TProjectInfo.GetAppType : string;
begin
  result := Trim(DefaultProperties.GetValue('AppType'));
end;

function TProjectInfo.GetDpmCompiler : string;
begin
  result := Trim(DefaultProperties.GetValue('DPMCompiler'));
end;

{ TDProjReader }

function TDProjReader.ReadFile(const fileName : string) : IProjectInfo;
begin
  if not TFile.Exists(fileName) then
    raise EDProjReadError.CreateFmt('project file not found: %s', [fileName]);
  result := ReadText(TFile.ReadAllText(fileName), fileName);
end;

function TDProjReader.ReadText(const xml : string; const fileName : string) : IProjectInfo;
var
  info : TProjectInfo;
begin
  info := TProjectInfo.Create(fileName);
  result := info;
  info.Load(xml);
end;

initialization
  // msxml is a com object, so the thread that reads a dproj has to be initialised
  CoInitializeEx(nil, COINIT_APARTMENTTHREADED or COINIT_DISABLE_OLE1DDE);

finalization
  CoUninitialize;

end.
