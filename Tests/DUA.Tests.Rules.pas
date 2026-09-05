unit DUA.Tests.Rules;

interface

uses
  DUnitX.TestFramework,
  DUA.Rules;

type
  [TestFixture]
  TRuleSetTests = class
  private
    function Given(const lines : array of string) : IRuleSet;
  public
    // --- reading a rule file ---
    [Test] procedure ABarePatternForbidsIt;
    [Test] procedure ABangInFrontAllowsIt;
    [Test] procedure BlankLinesAreSkipped;
    [Test] procedure AHashStartsAComment;
    [Test] procedure TwoSlashesStartAComment;
    [Test] procedure ACommentAfterARuleIsStripped;
    [Test] procedure SurroundingSpaceIsIgnored;
    [Test] procedure TheLineNumberIsKept;
    [Test] procedure ARuleFileOfNothingButCommentsHasNoRules;

    // --- what it refuses to read ---
    [Test] procedure ABangOnItsOwnIsAnError;
    [Test] procedure TwoPatternsOnOneLineAreAnError;
    [Test] procedure TheErrorNamesTheSourceAndLine;
    [Test] procedure TheErrorForTwoPatternsExplainsTheGrammar;

    // --- judging a unit ---
    [Test] procedure AUnitMatchingNothingIsFine;
    [Test] procedure AUnitMatchingAForbidIsInTrouble;
    [Test] procedure TheAnswerNamesThePatternThatCaughtIt;
    [Test] procedure AGlobCatchesTheWholeFamily;
    [Test] procedure MatchingIsCaseInsensitive;
    [Test] procedure APatternWithoutAWildcardMustMatchInFull;
    [Test] procedure AnAllowBeatsAForbid;
    [Test] procedure AnAllowWrittenBeforeTheForbidStillBeats;
    [Test] procedure AnAllowOnItsOwnForbidsNothing;
    [Test] procedure AnyOfAUnitsNamesCanBreakARule;
    [Test] procedure AnyOfAUnitsNamesCanExcuseIt;

    // --- where rules come from ---
    [Test] procedure SwitchesBecomeRules;
    [Test] procedure SwitchRulesHaveNoLineNumber;
    [Test] procedure EmptySwitchValuesAreIgnored;
    [Test] procedure CombiningKeepsBothSetsOfRules;
    [Test] procedure AnAllowFromASwitchExcusesAForbidFromAFile;
    [Test] procedure CombiningWithNothingIsSafe;
    [Test] procedure AMissingRulesFileIsAnError;

    // --- counting ---
    [Test] procedure ForbidCountIgnoresAllowRules;
  end;

implementation

uses
  System.SysUtils,
  Spring.Collections;

function TRuleSetTests.Given(const lines : array of string) : IRuleSet;
var
  values : TArray<string>;
  index : integer;
begin
  SetLength(values, Length(lines));
  for index := 0 to High(lines) do
    values[index] := lines[index];
  result := TRules.Parse(values, 'rules.txt');
end;

procedure TRuleSetTests.ABarePatternForbidsIt;
var
  rules : IRuleSet;
begin
  rules := Given(['Vcl.Forms']);
  Assert.AreEqual<integer>(1, rules.Rules.Count);
  Assert.IsFalse(rules.Rules[0].Allow);
  Assert.AreEqual('Vcl.Forms', rules.Rules[0].Pattern);
end;

procedure TRuleSetTests.ABangInFrontAllowsIt;
var
  rules : IRuleSet;
begin
  rules := Given(['!Vcl.Graphics']);
  Assert.IsTrue(rules.Rules[0].Allow);
  Assert.AreEqual('Vcl.Graphics', rules.Rules[0].Pattern);
end;

procedure TRuleSetTests.BlankLinesAreSkipped;
begin
  Assert.AreEqual<integer>(2, Given(['Vcl.*', '', '   ', 'Fmx.*']).Rules.Count);
end;

procedure TRuleSetTests.AHashStartsAComment;
begin
  Assert.AreEqual<integer>(1, Given(['# no gui in the service', 'Vcl.*']).Rules.Count);
end;

procedure TRuleSetTests.TwoSlashesStartAComment;
begin
  Assert.AreEqual<integer>(1, Given(['// no gui in the service', 'Vcl.*']).Rules.Count);
end;

procedure TRuleSetTests.ACommentAfterARuleIsStripped;
var
  rules : IRuleSet;
begin
  rules := Given(['!Vcl.Graphics   # the printer code needs TCanvas']);
  Assert.AreEqual('Vcl.Graphics', rules.Rules[0].Pattern);
end;

procedure TRuleSetTests.SurroundingSpaceIsIgnored;
begin
  Assert.AreEqual('Vcl.Forms', Given(['   Vcl.Forms   ']).Rules[0].Pattern);
  Assert.AreEqual('Vcl.Forms', Given(['  !  Vcl.Forms ']).Rules[0].Pattern);
end;

procedure TRuleSetTests.TheLineNumberIsKept;
var
  rules : IRuleSet;
begin
  // the point of keeping it is being able to say which line to go and change
  rules := Given(['# a comment', '', 'Vcl.*']);
  Assert.AreEqual(3, rules.Rules[0].Line);
end;

procedure TRuleSetTests.ARuleFileOfNothingButCommentsHasNoRules;
begin
  Assert.AreEqual<integer>(0, Given(['# nothing here', '// nor here', '']).Rules.Count);
end;

procedure TRuleSetTests.ABangOnItsOwnIsAnError;
begin
  Assert.WillRaise(
    procedure
    begin
      Given(['!']);
    end, ERulesError);
end;

procedure TRuleSetTests.TwoPatternsOnOneLineAreAnError;
begin
  // someone writing "forbid Vcl.*" in a syntax this does not have
  Assert.WillRaise(
    procedure
    begin
      Given(['forbid Vcl.*']);
    end, ERulesError);
end;

procedure TRuleSetTests.TheErrorNamesTheSourceAndLine;
var
  message : string;
begin
  message := '';
  try
    Given(['Vcl.*', '!']);
  except
    on e : ERulesError do
      message := e.Message;
  end;

  Assert.Contains(message, 'rules.txt');
  Assert.Contains(message, '(2)');
end;

procedure TRuleSetTests.TheErrorForTwoPatternsExplainsTheGrammar;
var
  message : string;
begin
  message := '';
  try
    Given(['forbid Vcl.*']);
  except
    on e : ERulesError do
      message := e.Message;
  end;

  Assert.Contains(message, 'one unit name or glob per line');
end;

procedure TRuleSetTests.AUnitMatchingNothingIsFine;
begin
  Assert.AreEqual('', Given(['Vcl.*']).ViolatedBy('System.Classes'));
end;

procedure TRuleSetTests.AUnitMatchingAForbidIsInTrouble;
begin
  Assert.AreNotEqual('', Given(['Vcl.Forms']).ViolatedBy('Vcl.Forms'));
end;

procedure TRuleSetTests.TheAnswerNamesThePatternThatCaughtIt;
begin
  Assert.AreEqual('Vcl.*', Given(['Fmx.*', 'Vcl.*']).ViolatedBy('Vcl.Forms'));
end;

procedure TRuleSetTests.AGlobCatchesTheWholeFamily;
var
  rules : IRuleSet;
begin
  rules := Given(['Vcl.*']);
  Assert.AreNotEqual('', rules.ViolatedBy('Vcl.Forms'));
  Assert.AreNotEqual('', rules.ViolatedBy('Vcl.Graphics'));
  Assert.AreEqual('', rules.ViolatedBy('Vclish.Thing'));
end;

procedure TRuleSetTests.MatchingIsCaseInsensitive;
begin
  Assert.AreNotEqual('', Given(['vcl.*']).ViolatedBy('VCL.FORMS'));
end;

procedure TRuleSetTests.APatternWithoutAWildcardMustMatchInFull;
begin
  // Forms is not a rule about Vcl.Forms, the same as everywhere else in this tool
  Assert.AreEqual('', Given(['Forms']).ViolatedBy('Vcl.Forms'));
end;

procedure TRuleSetTests.AnAllowBeatsAForbid;
begin
  Assert.AreEqual('', Given(['Vcl.*', '!Vcl.Graphics']).ViolatedBy('Vcl.Graphics'));
  Assert.AreNotEqual('', Given(['Vcl.*', '!Vcl.Graphics']).ViolatedBy('Vcl.Forms'));
end;

procedure TRuleSetTests.AnAllowWrittenBeforeTheForbidStillBeats;
begin
  // order in the file should not change the answer
  Assert.AreEqual('', Given(['!Vcl.Graphics', 'Vcl.*']).ViolatedBy('Vcl.Graphics'));
end;

procedure TRuleSetTests.AnAllowOnItsOwnForbidsNothing;
begin
  Assert.AreEqual('', Given(['!Vcl.Graphics']).ViolatedBy('Vcl.Forms'));
end;

procedure TRuleSetTests.AnyOfAUnitsNamesCanBreakARule;
var
  rules : IRuleSet;
begin
  // the source said Graphics and the compiler resolved Vcl.Graphics - a rule against
  // either name is a rule about the same unit
  rules := Given(['Graphics']);
  Assert.AreNotEqual('',
    rules.ViolatedByAny(TArray<string>.Create('Vcl.Graphics', 'Graphics')));
end;

procedure TRuleSetTests.AnyOfAUnitsNamesCanExcuseIt;
var
  rules : IRuleSet;
begin
  rules := Given(['Vcl.*', '!Graphics']);
  Assert.AreEqual('',
    rules.ViolatedByAny(TArray<string>.Create('Vcl.Graphics', 'Graphics')));
end;

procedure TRuleSetTests.SwitchesBecomeRules;
var
  rules : IRuleSet;
begin
  rules := TRules.FromSwitches(TArray<string>.Create('Vcl.*', 'Fmx.*'),
                               TArray<string>.Create('Vcl.Graphics'));
  Assert.AreEqual<integer>(3, rules.Rules.Count);
  Assert.AreEqual<integer>(2, rules.ForbidCount);
  Assert.AreEqual('', rules.ViolatedBy('Vcl.Graphics'));
  Assert.AreNotEqual('', rules.ViolatedBy('Fmx.Forms'));
end;

procedure TRuleSetTests.SwitchRulesHaveNoLineNumber;
var
  rules : IRuleSet;
begin
  rules := TRules.FromSwitches(TArray<string>.Create('Vcl.*'), nil);
  Assert.AreEqual(0, rules.Rules[0].Line, 'there is no line to send anyone to');
end;

procedure TRuleSetTests.EmptySwitchValuesAreIgnored;
var
  rules : IRuleSet;
begin
  rules := TRules.FromSwitches(TArray<string>.Create('Vcl.*', '', '   '), nil);
  Assert.AreEqual<integer>(1, rules.Rules.Count);
end;

procedure TRuleSetTests.CombiningKeepsBothSetsOfRules;
var
  rules : IRuleSet;
begin
  rules := TRules.Combine(Given(['Vcl.*']),
                          TRules.FromSwitches(TArray<string>.Create('Fmx.*'), nil));
  Assert.AreEqual<integer>(2, rules.ForbidCount);
  Assert.AreNotEqual('', rules.ViolatedBy('Vcl.Forms'));
  Assert.AreNotEqual('', rules.ViolatedBy('Fmx.Forms'));
end;

procedure TRuleSetTests.AnAllowFromASwitchExcusesAForbidFromAFile;
var
  rules : IRuleSet;
begin
  rules := TRules.Combine(Given(['Vcl.*']),
                          TRules.FromSwitches(nil, TArray<string>.Create('Vcl.Graphics')));
  Assert.AreEqual('', rules.ViolatedBy('Vcl.Graphics'));
end;

procedure TRuleSetTests.CombiningWithNothingIsSafe;
var
  rules : IRuleSet;
begin
  rules := TRules.Combine(Given(['Vcl.*']), nil);
  Assert.AreEqual<integer>(1, rules.ForbidCount);

  rules := TRules.Combine(nil, nil);
  Assert.AreEqual<integer>(0, rules.ForbidCount);
end;

procedure TRuleSetTests.AMissingRulesFileIsAnError;
begin
  Assert.WillRaise(
    procedure
    begin
      TRules.LoadFromFile('C:\no\such\file\rules.txt');
    end, ERulesError);
end;

procedure TRuleSetTests.ForbidCountIgnoresAllowRules;
begin
  Assert.AreEqual<integer>(1, Given(['Vcl.*', '!Vcl.Graphics', '!Vcl.Forms']).ForbidCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleSetTests);

end.
