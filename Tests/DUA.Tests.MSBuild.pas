unit DUA.Tests.MSBuild;

interface

uses
  DUnitX.TestFramework,
  DUA.Project.MSBuild;

type
  [TestFixture]
  TMSBuildPropertiesTests = class
  private
    FProperties : IMSBuildProperties;
  public
    [Setup]
    procedure Setup;

    [Test] procedure MissingPropertyIsAnEmptyString;
    [Test] procedure ValueCanBeReadBack;
    [Test] procedure NamesAreCaseInsensitive;
    [Test] procedure SettingAgainReplacesTheValue;
    [Test] procedure ContainsDistinguishesEmptyFromMissing;
  end;

  [TestFixture]
  TExpandTests = class
  private
    FProperties : IMSBuildProperties;
  public
    [Setup]
    procedure Setup;

    [Test] procedure TextWithNoReferencesIsUnchanged;
    [Test] procedure ExpandsASingleReference;
    [Test] procedure ExpandsSeveralReferences;
    [Test] procedure ExpandsTheSameReferenceTwice;
    [Test] procedure UnsetPropertyExpandsToNothing;
    [Test] procedure ReferenceNamesAreCaseInsensitive;
    [Test] procedure SelfReferenceAppendsToTheExistingValue;
    [Test] procedure DollarNotFollowedByParenIsLeftAlone;
    [Test] procedure UnterminatedReferenceIsLeftAlone;
    [Test] procedure FallsBackToEnvironmentVariables;
    [Test] procedure PropertyWinsOverEnvironmentVariable;
    [Test] procedure ExpandsARealisticSearchPath;
  end;

  [TestFixture]
  TConditionTests = class
  private
    FProperties : IMSBuildProperties;
    procedure AssertTrue(const condition : string);
    procedure AssertFalse(const condition : string);
  public
    [Setup]
    procedure Setup;

    [Test] procedure EmptyConditionIsTrue;
    [Test] procedure EqualityOfMatchingLiterals;
    [Test] procedure EqualityOfDifferentLiterals;
    [Test] procedure InequalityIsTheOpposite;
    [Test] procedure ComparisonIsCaseInsensitive;
    [Test] procedure SpacesAroundTheOperatorAreAllowed;
    [Test] procedure UnsetPropertyComparesAsEmpty;
    [Test] procedure NotEmptyTestOnAnUnsetPropertyIsFalse;
    [Test] procedure NotEmptyTestOnASetPropertyIsTrue;
    [Test] procedure AndRequiresBothSides;
    [Test] procedure OrRequiresEitherSide;
    [Test] procedure ParenthesesGroupTheOperands;
    [Test] procedure AndBindsTighterThanOr;
    [Test] procedure UnparseableConditionIsFalse;

    // the exact shapes the IDE writes into a dproj
    [Test] procedure RealBaseConfigCondition;
    [Test] procedure RealBasePlatformCondition;
    [Test] procedure RealConfigCondition;
    [Test] procedure RealConfigPlatformCondition;
    [Test] procedure RealConfigConditionForAnotherConfigIsFalse;
    [Test] procedure RealPlatformConditionForAnotherPlatformIsFalse;
    [Test] procedure RealDpmCacheDefaultCondition;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows;

{ TMSBuildPropertiesTests }

procedure TMSBuildPropertiesTests.Setup;
begin
  FProperties := TMSBuildProperties.Create;
end;

procedure TMSBuildPropertiesTests.MissingPropertyIsAnEmptyString;
begin
  Assert.AreEqual('', FProperties.GetValue('NoSuchProperty'));
end;

procedure TMSBuildPropertiesTests.ValueCanBeReadBack;
begin
  FProperties.SetValue('Config', 'Debug');
  Assert.AreEqual('Debug', FProperties.GetValue('Config'));
end;

procedure TMSBuildPropertiesTests.NamesAreCaseInsensitive;
begin
  FProperties.SetValue('Config', 'Debug');
  Assert.AreEqual('Debug', FProperties.GetValue('CONFIG'));
  Assert.AreEqual('Debug', FProperties.GetValue('config'));
end;

procedure TMSBuildPropertiesTests.SettingAgainReplacesTheValue;
begin
  FProperties.SetValue('Config', 'Debug');
  FProperties.SetValue('config', 'Release');
  Assert.AreEqual('Release', FProperties.GetValue('Config'));
end;

procedure TMSBuildPropertiesTests.ContainsDistinguishesEmptyFromMissing;
begin
  FProperties.SetValue('Empty', '');
  Assert.IsTrue(FProperties.Contains('Empty'), 'a property set to empty is still set');
  Assert.IsFalse(FProperties.Contains('Missing'));
end;

{ TExpandTests }

procedure TExpandTests.Setup;
begin
  FProperties := TMSBuildProperties.Create;
  FProperties.SetValue('Config', 'Debug');
  FProperties.SetValue('Platform', 'Win32');
end;

procedure TExpandTests.TextWithNoReferencesIsUnchanged;
begin
  Assert.AreEqual('C:\src\lib', TMSBuild.Expand('C:\src\lib', FProperties));
end;

procedure TExpandTests.ExpandsASingleReference;
begin
  Assert.AreEqual('Debug', TMSBuild.Expand('$(Config)', FProperties));
end;

procedure TExpandTests.ExpandsSeveralReferences;
begin
  Assert.AreEqual('Debug\Win32', TMSBuild.Expand('$(Config)\$(Platform)', FProperties));
end;

procedure TExpandTests.ExpandsTheSameReferenceTwice;
begin
  Assert.AreEqual('Win32-Win32', TMSBuild.Expand('$(Platform)-$(Platform)', FProperties));
end;

procedure TExpandTests.UnsetPropertyExpandsToNothing;
begin
  Assert.AreEqual('a-b', TMSBuild.Expand('a-$(NoSuchProperty)b', FProperties));
end;

procedure TExpandTests.ReferenceNamesAreCaseInsensitive;
begin
  Assert.AreEqual('Debug', TMSBuild.Expand('$(CONFIG)', FProperties));
end;

procedure TExpandTests.SelfReferenceAppendsToTheExistingValue;
begin
  // this is the idiom every dproj uses to inherit from the parent config
  FProperties.SetValue('DCC_UnitSearchPath', 'C:\base');
  Assert.AreEqual('C:\extra;C:\base',
    TMSBuild.Expand('C:\extra;$(DCC_UnitSearchPath)', FProperties));
end;

procedure TExpandTests.DollarNotFollowedByParenIsLeftAlone;
begin
  Assert.AreEqual('cost is $5', TMSBuild.Expand('cost is $5', FProperties));
end;

procedure TExpandTests.UnterminatedReferenceIsLeftAlone;
begin
  Assert.AreEqual('$(Config', TMSBuild.Expand('$(Config', FProperties));
end;

procedure TExpandTests.FallsBackToEnvironmentVariables;
begin
  SetEnvironmentVariable('DUA_TEST_VARIABLE', 'from-environment');
  try
    Assert.AreEqual('from-environment', TMSBuild.Expand('$(DUA_TEST_VARIABLE)', FProperties));
  finally
    SetEnvironmentVariable('DUA_TEST_VARIABLE', nil);
  end;
end;

procedure TExpandTests.PropertyWinsOverEnvironmentVariable;
begin
  SetEnvironmentVariable('DUA_TEST_VARIABLE', 'from-environment');
  try
    FProperties.SetValue('DUA_TEST_VARIABLE', 'from-project');
    Assert.AreEqual('from-project', TMSBuild.Expand('$(DUA_TEST_VARIABLE)', FProperties));
  finally
    SetEnvironmentVariable('DUA_TEST_VARIABLE', nil);
  end;
end;

procedure TExpandTests.ExpandsARealisticSearchPath;
begin
  FProperties.SetValue('DPMCache', 'C:\cache');
  FProperties.SetValue('DPMCompiler', 'delphi13.0');
  FProperties.SetValue('DPM', '$(DPMCache)\$(DPMCompiler)');

  // note DPM's own value is stored unexpanded, exactly as the dproj holds it, so
  // expanding it has to happen when it is used
  Assert.AreEqual('C:\cache\delphi13.0\VSoft.YAML\1.7.1\lib\Win32',
    TMSBuild.Expand(TMSBuild.Expand('$(DPM)\VSoft.YAML\1.7.1\lib\$(Platform)', FProperties), FProperties));
end;

{ TConditionTests }

procedure TConditionTests.Setup;
begin
  FProperties := TMSBuildProperties.Create;
  FProperties.SetValue('Config', 'Debug');
  FProperties.SetValue('Platform', 'Win32');
  FProperties.SetValue('Base', 'True');
end;

procedure TConditionTests.AssertTrue(const condition : string);
begin
  Assert.IsTrue(TMSBuild.EvaluateCondition(condition, FProperties), condition);
end;

procedure TConditionTests.AssertFalse(const condition : string);
begin
  Assert.IsFalse(TMSBuild.EvaluateCondition(condition, FProperties), condition);
end;

procedure TConditionTests.EmptyConditionIsTrue;
begin
  // an element with no Condition attribute always applies
  AssertTrue('');
end;

procedure TConditionTests.EqualityOfMatchingLiterals;
begin
  AssertTrue('''$(Config)''==''Debug''');
end;

procedure TConditionTests.EqualityOfDifferentLiterals;
begin
  AssertFalse('''$(Config)''==''Release''');
end;

procedure TConditionTests.InequalityIsTheOpposite;
begin
  AssertTrue('''$(Config)''!=''Release''');
  AssertFalse('''$(Config)''!=''Debug''');
end;

procedure TConditionTests.ComparisonIsCaseInsensitive;
begin
  // the dproj sets Base to 'True' in one group and compares against 'true' in the next
  AssertTrue('''$(Base)''==''true''');
end;

procedure TConditionTests.SpacesAroundTheOperatorAreAllowed;
begin
  AssertTrue('''$(Config)'' == ''Debug''');
end;

procedure TConditionTests.UnsetPropertyComparesAsEmpty;
begin
  AssertTrue('''$(NoSuchProperty)''==''''');
end;

procedure TConditionTests.NotEmptyTestOnAnUnsetPropertyIsFalse;
begin
  AssertFalse('''$(Cfg_1)''!=''''');
end;

procedure TConditionTests.NotEmptyTestOnASetPropertyIsTrue;
begin
  AssertTrue('''$(Base)''!=''''');
end;

procedure TConditionTests.AndRequiresBothSides;
begin
  AssertTrue('''$(Config)''==''Debug'' and ''$(Platform)''==''Win32''');
  AssertFalse('''$(Config)''==''Debug'' and ''$(Platform)''==''Win64''');
end;

procedure TConditionTests.OrRequiresEitherSide;
begin
  AssertTrue('''$(Config)''==''Release'' or ''$(Platform)''==''Win32''');
  AssertFalse('''$(Config)''==''Release'' or ''$(Platform)''==''Win64''');
end;

procedure TConditionTests.ParenthesesGroupTheOperands;
begin
  AssertTrue('(''$(Config)''==''Debug'')');
  AssertFalse('(''$(Config)''==''Release'' or ''$(Platform)''==''Win64'')');
end;

procedure TConditionTests.AndBindsTighterThanOr;
begin
  // Debug or (Win64 and Win64) - true because the left side holds
  AssertTrue('''$(Config)''==''Debug'' or ''$(Platform)''==''Win64'' and ''$(Platform)''==''Win64''');
end;

procedure TConditionTests.UnparseableConditionIsFalse;
begin
  AssertFalse('Exists(''$(BDS)\Bin\CodeGear.Delphi.Targets'')');
  AssertFalse('this is not a condition');
end;

procedure TConditionTests.RealBaseConfigCondition;
begin
  AssertTrue('''$(Config)''==''Base'' or ''$(Base)''!=''''');
end;

procedure TConditionTests.RealBasePlatformCondition;
begin
  AssertTrue('(''$(Platform)''==''Win32'' and ''$(Base)''==''true'') or ''$(Base_Win32)''!=''''');
end;

procedure TConditionTests.RealConfigCondition;
begin
  AssertTrue('''$(Config)''==''Debug'' or ''$(Cfg_2)''!=''''');
end;

procedure TConditionTests.RealConfigPlatformCondition;
begin
  FProperties.SetValue('Cfg_2', 'true');
  AssertTrue('(''$(Platform)''==''Win32'' and ''$(Cfg_2)''==''true'') or ''$(Cfg_2_Win32)''!=''''');
end;

procedure TConditionTests.RealConfigConditionForAnotherConfigIsFalse;
begin
  // Config is Debug, so the Release group must not apply
  AssertFalse('''$(Config)''==''Release'' or ''$(Cfg_1)''!=''''');
end;

procedure TConditionTests.RealPlatformConditionForAnotherPlatformIsFalse;
begin
  AssertFalse('(''$(Platform)''==''Win64'' and ''$(Base)''==''true'') or ''$(Base_Win64)''!=''''');
end;

procedure TConditionTests.RealDpmCacheDefaultCondition;
begin
  AssertTrue('''$(DPMCache)'' == ''''');
  FProperties.SetValue('DPMCache', 'C:\cache');
  AssertFalse('''$(DPMCache)'' == ''''');
end;

initialization
  TDUnitX.RegisterTestFixture(TMSBuildPropertiesTests);
  TDUnitX.RegisterTestFixture(TExpandTests);
  TDUnitX.RegisterTestFixture(TConditionTests);

end.
