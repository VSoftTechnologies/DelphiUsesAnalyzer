unit DUA.Tests.Conditionals;

interface

uses
  DUnitX.TestFramework,
  DUA.Types,
  DUA.Defines;

type
  /// <summary>
  ///   The {$IF} expression evaluator. Anything it cannot understand must come back as
  ///   unknown rather than a guess - the whole point is that the caller then takes every
  ///   branch and warns, instead of silently dropping a dependency.
  /// </summary>
  [TestFixture]
  TConditionalEvaluatorTests = class
  private
    FDefines : IDefineSet;
    function Eval(const expression : string) : TTriState;
    procedure AssertEval(const expected : TTriState; const expression : string);
  public
    [Setup]
    procedure Setup;

    // --- Defined() ---
    [Test] procedure DefinedIsTrueForADefinedSymbol;
    [Test] procedure DefinedIsFalseForAnUndefinedSymbol;
    [Test] procedure DefinedIsCaseInsensitiveInBothTheCallAndTheSymbol;
    [Test] procedure DefinedToleratesWhitespaceAroundTheArgument;

    // --- Declared() ---
    [Test] procedure DeclaredIsAlwaysUnknown;
    [Test] procedure NotDeclaredIsStillUnknown;

    // --- boolean literals ---
    [Test] procedure TrueLiteralIsTrue;
    [Test] procedure FalseLiteralIsFalse;

    // --- not / and / or ---
    [Test] procedure NotInvertsADefinedCheck;
    [Test] procedure AndRequiresBothSides;
    [Test] procedure OrRequiresEitherSide;
    [Test] procedure AndBindsTighterThanOr;
    [Test] procedure ParenthesesOverridePrecedence;
    [Test] procedure NestedParenthesesAreHandled;

    // --- unknown propagates by Kleene rules, not by infection ---
    [Test] procedure TrueOrUnknownIsTrue;
    [Test] procedure FalseAndUnknownIsFalse;
    [Test] procedure TrueAndUnknownIsUnknown;
    [Test] procedure FalseOrUnknownIsUnknown;

    // --- numeric comparison, against the TARGET compiler not ours ---
    [Test]
    [TestCase('ge lower',    'CompilerVersion >= 36,tsTrue')]
    [TestCase('ge exact',    'CompilerVersion >= 37,tsTrue')]
    [TestCase('ge higher',   'CompilerVersion >= 38,tsFalse')]
    [TestCase('gt',          'CompilerVersion > 36,tsTrue')]
    [TestCase('lt',          'CompilerVersion < 36,tsFalse')]
    [TestCase('le',          'CompilerVersion <= 37,tsTrue')]
    [TestCase('eq',          'CompilerVersion = 37,tsTrue')]
    [TestCase('ne',          'CompilerVersion <> 37,tsFalse')]
    [TestCase('decimal',     'CompilerVersion >= 36.0,tsTrue')]
    [TestCase('reversed',    '37 <= CompilerVersion,tsTrue')]
    [TestCase('rtlversion',  'RTLVersion >= 36,tsTrue')]
    procedure ComparisonsUseTheSeededNumericSymbols(const expression : string; const expected : string);

    [Test] procedure ComparisonOnAnUnknownSymbolIsUnknown;
    [Test] procedure ComparisonCombinesWithDefined;

    // --- things we cannot evaluate ---
    [Test] procedure BareIdentifierIsUnknown;
    [Test] procedure SizeOfExpressionIsUnknown;
    [Test] procedure EmptyExpressionIsUnknown;
    [Test] procedure UnbalancedParenthesisIsUnknown;
    [Test] procedure TrailingGarbageIsUnknown;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  DUA.Conditionals;

procedure TConditionalEvaluatorTests.Setup;
begin
  FDefines := TDefineSet.Create;
  FDefines.Define('MSWINDOWS');
  FDefines.Define('WIN32');
  FDefines.SetNumeric('CompilerVersion', 37.0);
  FDefines.SetNumeric('RTLVersion', 37.0);
end;

function TConditionalEvaluatorTests.Eval(const expression : string) : TTriState;
begin
  result := TConditionalEvaluator.Evaluate(expression, FDefines);
end;

procedure TConditionalEvaluatorTests.AssertEval(const expected : TTriState; const expression : string);
begin
  Assert.AreEqual(
    GetEnumName(TypeInfo(TTriState), Ord(expected)),
    GetEnumName(TypeInfo(TTriState), Ord(Eval(expression))),
    'evaluating: ' + expression);
end;

procedure TConditionalEvaluatorTests.DefinedIsTrueForADefinedSymbol;
begin
  AssertEval(tsTrue, 'Defined(MSWINDOWS)');
end;

procedure TConditionalEvaluatorTests.DefinedIsFalseForAnUndefinedSymbol;
begin
  AssertEval(tsFalse, 'Defined(LINUX)');
end;

procedure TConditionalEvaluatorTests.DefinedIsCaseInsensitiveInBothTheCallAndTheSymbol;
begin
  AssertEval(tsTrue, 'DEFINED(mswindows)');
  AssertEval(tsTrue, 'defined(MsWindows)');
end;

procedure TConditionalEvaluatorTests.DefinedToleratesWhitespaceAroundTheArgument;
begin
  AssertEval(tsTrue, 'Defined ( MSWINDOWS )');
end;

procedure TConditionalEvaluatorTests.DeclaredIsAlwaysUnknown;
begin
  AssertEval(tsUnknown, 'Declared(SomeConstant)');
end;

procedure TConditionalEvaluatorTests.NotDeclaredIsStillUnknown;
begin
  AssertEval(tsUnknown, 'not Declared(SomeConstant)');
end;

procedure TConditionalEvaluatorTests.TrueLiteralIsTrue;
begin
  AssertEval(tsTrue, 'True');
end;

procedure TConditionalEvaluatorTests.FalseLiteralIsFalse;
begin
  AssertEval(tsFalse, 'False');
end;

procedure TConditionalEvaluatorTests.NotInvertsADefinedCheck;
begin
  AssertEval(tsFalse, 'not Defined(MSWINDOWS)');
  AssertEval(tsTrue, 'not Defined(LINUX)');
end;

procedure TConditionalEvaluatorTests.AndRequiresBothSides;
begin
  AssertEval(tsTrue, 'Defined(MSWINDOWS) and Defined(WIN32)');
  AssertEval(tsFalse, 'Defined(MSWINDOWS) and Defined(LINUX)');
end;

procedure TConditionalEvaluatorTests.OrRequiresEitherSide;
begin
  AssertEval(tsTrue, 'Defined(LINUX) or Defined(WIN32)');
  AssertEval(tsFalse, 'Defined(LINUX) or Defined(ANDROID)');
end;

procedure TConditionalEvaluatorTests.AndBindsTighterThanOr;
begin
  // parsed as MSWINDOWS or (LINUX and ANDROID) = true or false = true.
  // if or bound tighter it would be (MSWINDOWS or LINUX) and ANDROID = false.
  AssertEval(tsTrue, 'Defined(MSWINDOWS) or Defined(LINUX) and Defined(ANDROID)');
end;

procedure TConditionalEvaluatorTests.ParenthesesOverridePrecedence;
begin
  AssertEval(tsFalse, '(Defined(MSWINDOWS) or Defined(LINUX)) and Defined(ANDROID)');
end;

procedure TConditionalEvaluatorTests.NestedParenthesesAreHandled;
begin
  AssertEval(tsTrue, '((Defined(MSWINDOWS)) and ((Defined(WIN32))))');
end;

procedure TConditionalEvaluatorTests.TrueOrUnknownIsTrue;
begin
  AssertEval(tsTrue, 'Defined(MSWINDOWS) or Declared(Whatever)');
end;

procedure TConditionalEvaluatorTests.FalseAndUnknownIsFalse;
begin
  AssertEval(tsFalse, 'Defined(LINUX) and Declared(Whatever)');
end;

procedure TConditionalEvaluatorTests.TrueAndUnknownIsUnknown;
begin
  AssertEval(tsUnknown, 'Defined(MSWINDOWS) and Declared(Whatever)');
end;

procedure TConditionalEvaluatorTests.FalseOrUnknownIsUnknown;
begin
  AssertEval(tsUnknown, 'Defined(LINUX) or Declared(Whatever)');
end;

procedure TConditionalEvaluatorTests.ComparisonsUseTheSeededNumericSymbols(const expression : string; const expected : string);
begin
  Assert.AreEqual(expected, GetEnumName(TypeInfo(TTriState), Ord(Eval(expression))),
    'evaluating: ' + expression);
end;

procedure TConditionalEvaluatorTests.ComparisonOnAnUnknownSymbolIsUnknown;
begin
  AssertEval(tsUnknown, 'SomeOtherVersion >= 3');
end;

procedure TConditionalEvaluatorTests.ComparisonCombinesWithDefined;
begin
  AssertEval(tsTrue, 'Defined(MSWINDOWS) and (CompilerVersion >= 36)');
  AssertEval(tsFalse, 'Defined(MSWINDOWS) and (CompilerVersion >= 99)');
end;

procedure TConditionalEvaluatorTests.BareIdentifierIsUnknown;
begin
  // {$IF SomeBooleanConst} is legal Delphi, but we have no way to know its value.
  AssertEval(tsUnknown, 'SomeBooleanConst');
end;

procedure TConditionalEvaluatorTests.SizeOfExpressionIsUnknown;
begin
  AssertEval(tsUnknown, 'SizeOf(Pointer) = 8');
end;

procedure TConditionalEvaluatorTests.EmptyExpressionIsUnknown;
begin
  AssertEval(tsUnknown, '');
  AssertEval(tsUnknown, '   ');
end;

procedure TConditionalEvaluatorTests.UnbalancedParenthesisIsUnknown;
begin
  AssertEval(tsUnknown, '(Defined(MSWINDOWS)');
end;

procedure TConditionalEvaluatorTests.TrailingGarbageIsUnknown;
begin
  AssertEval(tsUnknown, 'Defined(MSWINDOWS) $$$');
end;

initialization
  TDUnitX.RegisterTestFixture(TConditionalEvaluatorTests);

end.
