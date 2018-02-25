//
//  MGDecimal.swift
//  The MGDecimal struct provides a Swift-based interface to the decNumber C library.
//  You may use this library for personal use only.  There are no guarantees of
//  functionality for a given purpose.  If you do fix bugs, I'd appreciate getting
//  updates of the fixed source.
//
//  The main reason for this library was to provide an alternative to Apple's Decimal
//  library which has limited functionality and is restricted to only 38 digits.  I
//  have provided a rudimentary conversion from the Decimal type to the MGDecimal.
//  They are otherwise not compatible.  While you may use the MGDecimal type as is,
//  I recommend using the related ComplexDec type instead since it has support for
//  complex numbers and more mathematical functions.  Many of the complex number
//  routines are based on work by Dan Kogai in the complex.swift file.  I have
//  added some of the string conversions to this source to provide better init to/from
//  strings than the rather basic init functions provided by Dan.
//
//  Created by Mike Griebling on 4 Sep 2015.
//  Copyright © 2015-2018 Computer Inspirations. All rights reserved.
//
//  Notes: The maximum decimal number size is currently hard-limited to 120 digits
//  via DECNUMDIGITS.  The number of digits per exponent is fixed at six to allow
//  mathematical functions to work.
//

import Foundation
import LibDecNumber

public struct MGDecimal {
    
    public enum Round : UInt32 {
        // A bit kludgey -- I couldn't directly map the decNumber "rounding" enum to Swift.
        case ceiling,       /* round towards +infinity         */
        up,                 /* round away from 0               */
        halfUp,             /* 0.5 rounds up                   */
        halfEven,           /* 0.5 rounds to nearest even      */
        halfDown,           /* 0.5 rounds down                 */
        down,               /* round towards 0 (truncate)      */
        floor,              /* round towards -infinity         */
        r05Up,              /* round for reround               */
        max                 /* enum must be less than this     */
        
        init(_ r: rounding) { self = Round(rawValue: r.rawValue) ?? .halfUp }
        var crounding : rounding { return rounding(self.rawValue) }
    }
    
    public enum AngularMeasure {
        case radians, degrees, gradians
    }
    
    // Class properties
    static let maximumDigits = Int(DECNUMDIGITS)
    public static let nominalDigits = 38  // number of decimal digits in Apple's Decimal type
    static var context = decContext()
    static var defaultAngularMeasure = AngularMeasure.degrees
    
    // Internal number representation
    fileprivate var decimal = decNumber()
    fileprivate var angularMeasure = MGDecimal.defaultAngularMeasure
    
    private static let errorFlags = UInt32(DEC_IEEE_754_Division_by_zero | DEC_IEEE_754_Overflow |
        DEC_IEEE_754_Underflow | DEC_Conversion_syntax | DEC_Division_impossible |
        DEC_Division_undefined | DEC_Insufficient_storage | DEC_Invalid_context | DEC_Invalid_operation)
    
    private func initContext(digits: Int) {
        if MGDecimal.context.digits == 0 && digits <= MGDecimal.maximumDigits {
            decContextDefault(&MGDecimal.context, DEC_INIT_BASE)
            MGDecimal.context.traps = 0
            MGDecimal.context.digits = Int32(digits)
//            Decimal.context.round = Round.HalfEven.crounding  // used in banking
//            Decimal.context.round = Round.HalfUp.crounding    // default if not specified
        }
    }
    
    // MARK: - Internal Constants
    
    public static let pi = MGDecimal(
        "3.141592653589793238462643383279502884197169399375105820974944592307816406286" +
        "208998628034825342117067982148086513282306647093844609550582231725359408128481" +
        "117450284102701938521105559644622948954930381964428810975665933446128475648233" +
        "786783165271201909145648566923460348610454326648213393607260249141273724587006", digits: maximumDigits)!
    
    public static let π = pi
    public static let zero = MGDecimal(0)
    public static let one = MGDecimal(1)
    public static let two = MGDecimal(2)
    
    public static var infinity : MGDecimal { var x = zero; x.setINF(); return x }
    fileprivate static var Nil : MGDecimal?
    public static var NaN : MGDecimal { var x = zero; x.setNAN(); return x }
    public static var sNaN : MGDecimal { var x = zero; x.setsNAN(); return x }
    fileprivate static let _2pi = two * pi
    fileprivate static let pi_2 = pi / two
    
    public static let greatestFiniteMagnitude = MGDecimal(
        "9.99999999999999999999999999999999999999999999999999999999999999999999999999999" +
        "9999999999999999999999999999999999999999999999999999999999999999999999999999999" +
        "9999999999999999999999999999999999999999999999999999999999999999999999999999999" +
        "9999999999999999999999999999999999999999999999999999999999999999999999999999999e999999999",
        digits: maximumDigits)!
    
    public static var leastNormalMagnitude = MGDecimal(
        "9.99999999999999999999999999999999999999999999999999999999999999999999999999999" +
        "9999999999999999999999999999999999999999999999999999999999999999999999999999999" +
        "9999999999999999999999999999999999999999999999999999999999999999999999999999999" +
        "9999999999999999999999999999999999999999999999999999999999999999999999999999999e-999999999",
        digits: maximumDigits)!
    
    /// Takes into account infinity and NaN
    public func isTotallyOrdered(belowOrEqualTo other: MGDecimal) -> Bool {
        var b = other
        var a = decimal
        var result = decNumber()
        decNumberCompareTotalMag(&result, &a, &b.decimal, &MGDecimal.context)
        let ai = decNumberToInt32(&result, &MGDecimal.context)
        return ai <= 0
    }
    
    public static let radix = 10
    
    // MARK: - Status Methods
    
    public static var errorString : String {
        let flags = context.status & errorFlags
        if flags == 0 { return "" }
        context.status &= errorFlags
        let errorString = decContextStatusToString(&context)
        return String(cString: errorString!)
    }
    
    public static func clearStatus() { decContextZeroStatus(&context) }
    
    public static var roundMethod : Round {
        get { return Round(decContextGetRounding(&MGDecimal.context)) }
        set { decContextSetRounding(&MGDecimal.context, newValue.crounding) }
    }
    
    public static var digits : Int {
        get { return Int(context.digits) }
        set { if newValue > 0 && newValue <= maximumDigits { context.digits = Int32(newValue) } }
    }
    
    public var nextUp: MGDecimal {
        var a = decimal
        var result = decNumber()
        if isNegative {
            decNumberNextMinus(&result, &a, &MGDecimal.context)
        } else {
            decNumberNextPlus(&result, &a, &MGDecimal.context)
        }
        return MGDecimal(result)
    }
    
    public mutating func round(_ rule: FloatingPointRoundingRule) {
        let rounding = MGDecimal.roundMethod // save current setting
        switch rule {
        case .awayFromZero :            MGDecimal.roundMethod = .up
        case .down :                    MGDecimal.roundMethod = .floor
        case .toNearestOrAwayFromZero:  MGDecimal.roundMethod = .halfUp
        case .toNearestOrEven:          MGDecimal.roundMethod = .halfEven
        case .towardZero:               MGDecimal.roundMethod = .down
        case .up:                       MGDecimal.roundMethod = .ceiling
        }
        var a = decimal
        var result = decNumber()
        decNumberToIntegralValue(&result, &a, &MGDecimal.context)
        decimal = result
        MGDecimal.roundMethod = rounding  // restore original setting
    }
    
    public var significand: MGDecimal {
        var a = decimal
        var zero = MGDecimal.zero.decimal
        var result = decNumber()
        decNumberRescale(&result, &a, &zero, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public mutating func formRemainder(dividingBy other: MGDecimal) {
        var a = decimal
        var b = other.decimal
        var result = decNumber()
        decNumberRemainderNear(&result, &a, &b, &MGDecimal.context)
        decimal = result
    }
    
    public mutating func formTruncatingRemainder(dividingBy other: MGDecimal) {
        var a = decimal
        var b = other.decimal
        var result = decNumber()
        decNumberRemainder(&result, &a, &b, &MGDecimal.context)
        decimal = result
    }
    
    // MARK: - Initialization Methods
    
    public init() { self.init(0) }    // default value is 0
    
    public init(_ decimal : MGDecimal) { self.decimal = decimal.decimal }
    
    public init(_ uint: UInt) {
        initContext(digits: MGDecimal.nominalDigits)
        if uint <= UInt(UInt32.max) && uint >= UInt(UInt32.min)  {
            decNumberFromUInt32(&decimal, UInt32(uint))
        } else {
            /* do this the long way */
            let working = uint
            var x = MGDecimal.zero
            var n = working
            var m = MGDecimal.one
            while n != 0 {
                let r = n % 10; n /= 10
                if r != 0 { x += m * MGDecimal(r) }
                m *= 10
            }
            decimal = x.decimal
        }
    }
    
    public init(_ int: Int) {
        /* small integers (32-bits) are directly convertible */
        initContext(digits: MGDecimal.nominalDigits)
        if int <= Int(Int32.max) && int >= Int(Int32.min)  {
            decNumberFromInt32(&decimal, Int32(int))
        } else if int == Int.min {
            // tricky because Int can't represent -Int.min
            let x = -MGDecimal(UInt(Int.max)+1)  // Int.max+1 = -Int.min
            decimal = x.decimal
        } else {
            /* do this the long way */
            var x = MGDecimal(UInt(Swift.abs(int)))
            if int < 0 { x = -x }
            decimal = x.decimal
        }
    }
    
    public init(sign: FloatingPointSign, exponent: Int, significand: MGDecimal) {
        var a = significand
        var exp = MGDecimal(exponent)
        var result = decNumber()
        decNumberRescale(&result, &a.decimal, &exp.decimal, &MGDecimal.context)
        if sign == .minus {
            decNumberCopyNegate(&decimal, &result)
        } else {
            decimal = result
        }
    }
    
    public init(signOf: MGDecimal, magnitudeOf: MGDecimal) {
        var result = decNumber()
        var a = magnitudeOf.decimal
        var sign = signOf.decimal
        decNumberCopySign(&result, &a, &sign)
        decimal = result
    }
    
    public init(_ decimal: Foundation.Decimal) {
        // we cheat since this should be an uncommon thing to do
        let numStr = decimal.description
        self.init(numStr, digits: 38)!  // Apple Decimals are 38 digits fixed
    }
    
    private static func digitToInt(_ digit: Character) -> Int? {
        let radixDigits = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        if let digitIndex = radixDigits.index(of: digit) {
            return radixDigits.distance(from: radixDigits.startIndex, to:digitIndex)
        }
        return nil   // Error illegal radix character
    }
    
    public init?(_ s: String, digits: Int = 0, radix: Int = 10) {
        let digits = digits == 0 ? MGDecimal.nominalDigits : digits
        initContext(digits: digits)
        let ls = s.replacingOccurrences(of: "_", with: "").uppercased()  // remove underscores
        if radix == 10 {
            // use library function for string conversion
            decNumberFromString(&decimal, ls, &MGDecimal.context)
        } else {
            // convert non-base 10 string to a Decimal number
            var number = MGDecimal.zero
            let radixNumber = MGDecimal(radix)
            for digit in ls {
                if let digitNumber = MGDecimal.digitToInt(digit) {
                    number = number * radixNumber + MGDecimal(digitNumber)
                } else {
                    return nil
                }
            }
            decimal = number.decimal
        }
    }
    
    public init(_ s: [UInt8], exponent: Int = 0) {
        var s = s
        initContext(digits: s.count)
        decNumberSetBCD(&decimal, &s, UInt32(s.count))
        var exp = decNumber()
        decNumberFromInt32(&exp, Int32(exponent))
        var result = decNumber()
        decNumberScaleB(&result, &decimal, &exp, &MGDecimal.context)
        decimal = result
    }
    
    fileprivate init(_ d: decNumber) {
        initContext(digits: Int(d.digits))
        decimal = d
    }
    
    // MARK: - Accessor Operations 
    
    public var engineeringString : String {
        var cs = [CChar](repeating: 0, count: Int(decimal.digits+14))
        var local = decimal
        decNumberToEngString(&local, &cs)
        return String(cString: &cs)
    }
    
    private func getRadixDigitFor(_ n: Int) -> String {
        if n < 10 {
            return String(n)
        } else {
            let offset = n - 10
            let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            let digit = letters[letters.index(letters.startIndex, offsetBy: offset)]
            return String(digit)
        }
    }
    
    private func getMiniRadixDigits(_ radix: Int) -> String {
        var result = ""
        var radix = radix
        let miniDigits = "₀₁₂₃₄₅₆₇₈₉"
        while radix > 0 {
            let offset = radix % 10; radix /= 10
            let digit = miniDigits[miniDigits.index(miniDigits.startIndex, offsetBy: offset)]
            result = String(digit) + result
        }
        return result
    }
    
    private func convert (fromBase from: Int, toBase base: Int) -> MGDecimal {
        let oldDigits = MGDecimal.digits
        MGDecimal.digits = MGDecimal.maximumDigits
        let to = MGDecimal(base)
        let from = MGDecimal(from)
        var y = MGDecimal.zero
        var n = self
        var scale = MGDecimal.one
        while !n.isZero {
            let digit = n % to
            y += scale * digit
            n = n.idiv(to)
            scale *= from
        }
        MGDecimal.digits = oldDigits
        return y
    }
    
    public func string(withRadix radix : Int, showBase : Bool = false) -> String {
        var n = self.integer.abs
        
        // restrict to legal radix values 2 to 36
        let dradix = MGDecimal(Swift.min(36, Swift.max(radix, 2)))
        var str = ""
        while !n.isZero {
            let digit = n % dradix
            n = n.idiv(dradix)
            str = getRadixDigitFor(digit.int) + str
        }
        if showBase { str += getMiniRadixDigits(radix) }
        return str
    }
    
    public static var decNumberVersionString : String {
        return String(cString: decNumberVersion())
    }
    
    public var int : Int {
        var local = decimal
        if self <= MGDecimal(Int(Int32.max)) && self >= MGDecimal(Int(Int32.min)) {
            return Int(decNumberToInt32(&local, &MGDecimal.context))
        } else if self < MGDecimal(Int.min) {
            return Int.min
        } else if self > MGDecimal(Int.max) {
            return Int.max
        } else {
            return Int(description) ?? 0
        }
    }
    
    public var uint : UInt {
        var local = decimal
        if self <= MGDecimal(UInt(UInt32.max)) {
            return UInt(decNumberToUInt32(&local, &MGDecimal.context))
        } else if self > MGDecimal(UInt.max) {
            return UInt.max
        } else {
            return UInt(description) ?? 0
        }
    }
    
    /// Returns the type of number (e.g., "NaN", "+Normal", etc.)
    public var numberClass : String {
        var a = decimal
        let cs = decNumberClassToString(decNumberClass(&a, &MGDecimal.context))
        return String(cString: cs!)
    }
    
    public var floatingPointClass: FloatingPointClassification {
        var a = self.decimal
        let c = decNumberClass(&a, &MGDecimal.context)
        switch c {
        case DEC_CLASS_SNAN: return .signalingNaN
        case DEC_CLASS_QNAN: return .quietNaN
        case DEC_CLASS_NEG_INF: return .negativeInfinity
        case DEC_CLASS_POS_INF: return .positiveInfinity
        case DEC_CLASS_NEG_ZERO: return .negativeZero
        case DEC_CLASS_POS_ZERO: return .positiveZero
        case DEC_CLASS_NEG_NORMAL: return .negativeNormal
        case DEC_CLASS_POS_NORMAL: return .positiveNormal
        case DEC_CLASS_POS_SUBNORMAL: return .positiveSubnormal
        case DEC_CLASS_NEG_SUBNORMAL: return .negativeSubnormal
        default: return .positiveZero
        }
    }
    
    /// Returns all digits of the binary-coded decimal (BCD) digits of the number with
    /// one value (0 to 9) per byte.
    public var bcd : [UInt8] {
        var result = [UInt8](repeating: 0, count: Int(decimal.digits))
        var a = decimal
        decNumberGetBCD(&a, &result)
        return result
    }
    
    public var exponent : Int { return Int(decimal.exponent) }
    public var eps : MGDecimal {
        var local = decimal
        var result = decNumber()
        decNumberNextPlus(&result, &local, &MGDecimal.context)
        var result2 = decNumber()
        decNumberSubtract(&result2, &result, &local, &MGDecimal.context)
        return MGDecimal(result2)
    }
    
    private let DECSPECIAL = UInt8(DECINF|DECNAN|DECSNAN)
    public var isFinite : Bool   { return decimal.bits & DECSPECIAL == 0 }
    public var isInfinite: Bool  { return decimal.bits & UInt8(DECINF) != 0 }
    public var isNaN: Bool       { return decimal.bits & UInt8(DECNAN|DECSNAN) != 0 }
    public var isNegative: Bool  { return decimal.bits & UInt8(DECNEG) != 0 }
    public var isZero: Bool      { return isFinite && decimal.digits == 1 && decimal.lsu.0 == 0 }
    public var isSubnormal: Bool { var n = decimal; return decNumberIsSubnormal(&n, &MGDecimal.context) == 1 }
    public var isSpecial: Bool   { return decimal.bits & DECSPECIAL != 0 }
    public var isCanonical: Bool { return true }
    public var isInteger: Bool {
        var local = decimal
        var result = decNumber()
        decNumberToIntegralExact(&result, &local, &MGDecimal.context)
        if MGDecimal.context.status & UInt32(DEC_Inexact) != 0 {
            decContextClearStatus(&MGDecimal.context, UInt32(DEC_Inexact)); return false
        }
        return true
    }

    // MARK: - Basic Operations
    
    /// Removes all trailing zeros without changing the value of the number.
    public func normalize () -> MGDecimal {
        var a = decimal
        var result = decNumber()
        decNumberNormalize(&result, &a, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    /// Converts the number to an integer representation without any fractional digits.
    /// The active rounding mode is used during this conversion.
    public var integer : MGDecimal {
        var a = decimal
        var result = decNumber()
        decNumberToIntegralValue(&result, &a, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func remainder (_ b: MGDecimal) -> MGDecimal {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberRemainder(&result, &a,  &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func negate () -> MGDecimal {
        var a = decimal
        var result = decNumber()
        decNumberMinus(&result, &a, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func max (_ b: MGDecimal) -> MGDecimal {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberMax(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func min (_ b: MGDecimal) -> MGDecimal {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberMin(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public var abs : MGDecimal {
        var a = decimal
        var result = decNumber()
        decNumberAbs(&result, &a, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func add (_ b: MGDecimal) -> MGDecimal {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberAdd(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func sub (_ b: MGDecimal) -> MGDecimal {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberSubtract(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func mul (_ b: MGDecimal) -> MGDecimal {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberMultiply(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func div (_ b: MGDecimal) -> MGDecimal {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberDivide(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func idiv (_ b: MGDecimal) -> MGDecimal {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberDivideInteger(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    /// Returns *self* + *b* x *c* or multiply accumulate with only the final rounding.
    public func mulAcc (_ b: MGDecimal, c: MGDecimal) -> MGDecimal {
        var b = b
        var c = c
        var a = decimal
        var result = decNumber()
        decNumberFMA(&result, &c.decimal, &b.decimal, &a, &MGDecimal.context)
        return MGDecimal(result)
    }

    /// Rounds to *digits* places where negative values limit the decimal places
    /// and positive values limit the number to multiples of 10 ** digits.
    public func round (_ digits: Int) -> MGDecimal {
        var a = decimal
        var b = MGDecimal(digits)
        var result = decNumber()
        decNumberRescale(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    // MARK: - Scientific Operations
    
    public func pow (_ b: MGDecimal) -> MGDecimal {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberPower(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func exp () -> MGDecimal {
        var a = decimal
        var result = decNumber()
        decNumberExp(&result, &a, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    /// Natural logarithm
    public func ln () -> MGDecimal {
        var a = decimal
        var result = decNumber()
        decNumberLn(&result, &a, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func log10 () -> MGDecimal {
        var a = decimal
        var result = decNumber()
        decNumberLog10(&result, &a, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    /// Returns self * 10 ** b
    public func scaleB (_ b: MGDecimal) -> MGDecimal {
        var a = decimal
        var result = decNumber()
        decNumberLogB(&result, &a, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func sqrt () -> MGDecimal {
        var a = decimal
        var result = decNumber()
        decNumberSquareRoot(&result, &a, &MGDecimal.context)
        return MGDecimal(result)
    }
    
    public func cbrt () -> MGDecimal {
        var a = decimal
        var b = MGDecimal(3).decimal
        var c = MGDecimal.one.decimal
        var result = decNumber()
        decNumberDivide(&result, &c, &b, &MGDecimal.context)  // get 1/3
        decNumberCopy(&b, &result)
        decNumberPower(&result, &a, &b, &MGDecimal.context)   // self ^ (1/3)
        return MGDecimal(result)
    }
    
    /// returns sqrt(self² + y²)
    public func hypot(y : MGDecimal) -> MGDecimal {
        var x = self.abs
        let y = y.abs
        var t = x.min(y)
        x = x.max(y)
        t /= x
        return x*(1+t*t).sqrt()
    }
    
    
    // MARK: - Logical Operations
    
    public func or (_ b: MGDecimal) -> MGDecimal {
        var b = b.logical()
        var a = logical().decimal
        var result = decNumber()
        decNumberOr(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result).base10()
    }
    
    public func and (_ b: MGDecimal) -> MGDecimal {
        var b = b.logical()
        var a = logical().decimal
        var result = decNumber()
        decNumberAnd(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result).base10()
    }
    
    public func xor (_ b: MGDecimal) -> MGDecimal {
        var b = b.logical()
        var a = logical().decimal
        var result = decNumber()
        decNumberXor(&result, &a, &b.decimal, &MGDecimal.context)
        return MGDecimal(result).base10()
    }
    
    public func not () -> MGDecimal {
        var a = logical().decimal
        var result = decNumber()
        decNumberInvert(&result, &a, &MGDecimal.context)
        return MGDecimal(result).base10()
    }
    
    public func shift (_ bits: MGDecimal) -> MGDecimal {
        var bits = bits
        var a = logical().decimal
        var result = decNumber()
        decNumberShift(&result, &a, &bits.decimal, &MGDecimal.context)
        return MGDecimal(result).base10()
    }
    
    public func rotate (_ bits: MGDecimal) -> MGDecimal {
        var bits = bits
        var a = logical().decimal
        var result = decNumber()
        decNumberRotate(&result, &a, &bits.decimal, &MGDecimal.context)
        return MGDecimal(result).base10()
    }
    
    public func logical () -> MGDecimal {
        // converts decimal numbers to logical
        return integer.abs.convert(fromBase: 10, toBase: 2)
    }
    
    public func base10 () -> MGDecimal {
        // converts logical numbers to decimal
        return convert(fromBase: 2, toBase: 10)
    }
}

//
// Trigonometric functions
//

public extension MGDecimal {
    
    public static var SINCOS_DIGITS : Int { return MGDecimal.maximumDigits }
    
    /* Check for right angle multiples and if exact, return the apropriate
     * quadrant constant directly.
     */
    private static func rightAngle(res: inout MGDecimal, x: MGDecimal, quad: MGDecimal, r0: MGDecimal, r1: MGDecimal, r2: MGDecimal, r3: MGDecimal) -> Bool {
        var r = x % quad // decNumberRemainder(&r, x, quad, &Ctx);
        if r.isZero { return false }
        if x.isZero {
            res = r0
        } else {
            r = quad + quad // dn_add(&r, quad, quad); dn_compare(&r, &r, x);
            if r == x {
                res = r2
            } else if r.isNegative {
                res = r3
            } else {
                res = r1
            }
        }
        return true
    }
    
    private static func convertToRadians (res: inout MGDecimal, x: MGDecimal, r0: MGDecimal, r1: MGDecimal, r2: MGDecimal, r3: MGDecimal) -> Bool {
        let circle, right : MGDecimal
        switch x.angularMeasure {
        case .radians:  res = x % _2pi; return true // no conversion needed - just reduce the range
        case .degrees:  circle = 360; right = 90
        case .gradians: circle = 400; right = 100
        }
        var fm = x % circle
        if fm.isNegative { fm += circle }
        if rightAngle(res: &res, x: fm, quad: right, r0: r0, r1: r1, r2: r2, r3: r3) { return false }
        res = fm * MGDecimal._2pi / circle
        return true
    }
    
    private static func convertFromRadians (res: inout MGDecimal, x: MGDecimal) {
        let circle: MGDecimal
        switch x.angularMeasure {
        case .radians:  res = x; return    // no conversion needed
        case .degrees:  circle = 360
        case .gradians: circle = 400
        }
        res = x * circle / MGDecimal._2pi
    }
    
    private static func sincosTaylor(_ a : MGDecimal, sout: inout MGDecimal?, cout: inout MGDecimal?) {
        var a2, t, j, z, s, c : MGDecimal
        let digits = MGDecimal.digits
        MGDecimal.digits = SINCOS_DIGITS
        
        a2 = a.sqr()  // dn_multiply(&a2.n, a, a);
        j = MGDecimal.one         // dn_1(&j.n);
        t = MGDecimal.one         // dn_1(&t.n);
        s = MGDecimal.one         // dn_1(&s.n);
        c = MGDecimal.one         // dn_1(&c.n);
        
        var fins = sout == nil
        var finc = cout == nil
        for i in 1..<1000 where !(fins && finc) {
            let odd = (i & 1) != 0
            
            j += MGDecimal.one // dn_inc(&j.n);
            z = a2 / j      // dn_divide(&z.n, &a2.n, &j.n);
            t *= z          // dn_multiply(&t.n, &t.n, &z.n);
            if !finc {
                z = c       // decNumberCopy(&z.n, &c.n);
                if odd {
                    c -= t  // dn_subtract(&c.n, &c.n, &t.n);
                } else {
                    c += t  // dn_add(&c.n, &c.n, &t.n);
                }
                if c == z { finc = true }
            }
            
            j += MGDecimal.one // dn_inc(&j.n);
            t /= j          // dn_divide(&t.n, &t.n, &j.n);
            if !fins {
                z = s       // decNumberCopy(&z.n, &s.n);
                if odd {
                    s -= t  // dn_subtract(&s.n, &s.n, &t.n);
                } else {
                    s += t  // dn_add(&s.n, &s.n, &t.n);
                }
                if s == z { fins = true }
            }
        }
        
        // round to the required number of digits
        MGDecimal.digits = digits
        if sout != nil {
            sout = s * a    // dn_multiply(sout, &s.n, a);
        }
        if cout != nil {
            cout = c + MGDecimal.zero    // dn_plus(cout, &c.n);
        }
    }
    
    private static func atan(res: inout MGDecimal, x: MGDecimal) {
        var a, b, a2, t, j, z, last : MGDecimal
        var doubles = 0
        let neg = x.isNegative
        
        // arrange for a >= 0
        if neg {
            a = -x  // dn_minus(&a, x);
        } else {
            a = x   // decNumberCopy(&a, x);
        }
        
        // reduce range to 0 <= a < 1, using atan(x) = pi/2 - atan(1/x)
        let invert = a > MGDecimal.one
        if invert { a = MGDecimal.one / a } // dn_divide(&a, &const_1, &a);
        
        // Range reduce to small enough limit to use taylor series
        // using:
        //  tan(x/2) = tan(x)/(1+sqrt(1+tan(x)^2))
        for _ in 0..<1000 {
            if a <= MGDecimal("0.1") { break }
            doubles += 1
            // a = a/(1+sqrt(1+a^2)) -- at most 3 iterations.
            b = a.sqr()      // dn_multiply(&b, &a, &a);
            b += MGDecimal.one // dn_inc(&b);
            b = b.sqrt()     // dn_sqrt(&b, &b);
            b += MGDecimal.one // dn_inc(&b);
            a /= b           // dn_divide(&a, &a, &b);
        }
        
        // Now Taylor series
        // tan(x) = x(1-x^2/3+x^4/5-x^6/7...)
        // We calculate pairs of terms and stop when the estimate doesn't change
        res = 3         // , &const_3);
        j = 5           // decNumberCopy(&j, &const_5);
        a2 = a.sqr()    // dn_multiply(&a2, &a, &a);	// a^2
        t = a2          // decNumberCopy(&t, &a2);
        res = t / res   // dn_divide(res, &t, res);	// s = 1-t/3 -- first two terms
        res = MGDecimal.one - res   // dn_1m(res, res);
        
        repeat {	// Loop until there is no digits changed
            last = res
            
            t *= a2     // dn_multiply(&t, &t, &a2);
            z = t / j   // dn_divide(&z, &t, &j);
            res += z    // dn_add(res, res, &z);
            j += MGDecimal.two // dn_p2(&j, &j);
            
            t *= a2     // dn_multiply(&t, &t, &a2);
            z = t / j   // dn_divide(&z, &t, &j);
            res += z    // dn_subtract(res, res, &z);
            j += MGDecimal.two  // dn_p2(&j, &j);
        } while res != last
        res *= a        // dn_multiply(res, res, &a);
        
        while doubles > 0 {
            res += res      // dn_add(res, res, res);
            doubles -= 1
        }
        
        if invert {
            res = MGDecimal.pi_2 - res // dn_subtract(res, &const_PIon2, res);
        }
        
        if neg { res = -res } // dn_minus(res, res);
    }
    
    private static func atan2(y: MGDecimal, x: MGDecimal) -> MGDecimal {
        let xneg = x.isNegative
        let yneg = y.isNegative
        var at = MGDecimal.zero
        
        if x.isNaN || y.isNaN { return MGDecimal.NaN }
        if y.isZero {
            if yneg {
                if x.isZero {
                    if xneg {
                        at = -MGDecimal.pi
                    } else {
                        at = y
                    }
                } else if xneg {
                    at = -MGDecimal.pi //decNumberPI(at);
                } else {
                    at = y  // decNumberCopy(at, y);
                }
            } else {
                if x.isZero {
                    if xneg {
                        at = MGDecimal.pi // decNumberPI(at);
                    } else {
                        at = MGDecimal.zero // decNumberZero(at);
                    }
                } else if xneg {
                    at = MGDecimal.pi     // decNumberPI(at);
                } else {
                    at = MGDecimal.zero   // decNumberZero(at);
                }
            }
            return at
        }
        if x.isZero  {
            at = MGDecimal.pi_2 // decNumberPIon2(at);
            if yneg { at = -at } //  dn_minus(at, at);
            return at
        }
        if x.isInfinite {
            if xneg {
                if y.isInfinite {
                    at = MGDecimal.pi * 0.75  // decNumberPI(&t);
                    // dn_multiply(at, &t, &const_0_75);
                    if yneg { at = -at } // dn_minus(at, at);
                } else {
                    at = MGDecimal.pi // decNumberPI(at);
                    if yneg { at = -at } // dn_minus(at, at);
                }
            } else {
                if y.isInfinite {
                    at = MGDecimal.pi/4    // decNumberPIon2(&t);
                    if yneg { at = -at } // dn_minus(at, at);
                } else {
                    at = MGDecimal.zero    // decNumberZero(at);
                    if yneg { at = -at } // dn_minus(at, at);
                }
            }
            return at
        }
        if y.isInfinite  {
            at = MGDecimal.pi_2    // decNumberPIon2(at);
            if yneg { at = -at } //  dn_minus(at, at);
            return at
        }
        
        var t = y / x       // dn_divide(&t, y, x);
        var r = MGDecimal.zero
        MGDecimal.atan(res: &r, x: t) // do_atan(&r, &t);
        if xneg {
            t = MGDecimal.pi // decNumberPI(&t);
            if yneg { t = -t } // dn_minus(&t, &t);
        } else {
            t = MGDecimal.zero // decNumberZero(&t);
        }
        at = r + t  // dn_add(at, &r, &t);
        if at.isZero && yneg { at = -at } //  dn_minus(at, at);
        return at
    }
    
    private static func asin(res: inout MGDecimal, x: MGDecimal) {
        if x.isNaN { res.setNAN(); return }
        
        var abx = x.abs //dn_abs(&abx, x);
        if abx > MGDecimal.one { res.setNAN(); return }
        
        // res = 2*atan(x/(1+sqrt(1-x*x)))
        var z = x.sqr()      // dn_multiply(&z, x, x);
        z = MGDecimal.one - z  // dn_1m(&z, &z);
        z = z.sqrt()         // dn_sqrt(&z, &z);
        z += MGDecimal.one     // dn_inc(&z);
        z = x / z            // dn_divide(&z, x, &z);
        MGDecimal.atan(res: &abx, x: z) // do_atan(&abx, &z);
        res = 2 * abx       // dn_mul2(res, &abx);
    }
    
    private static func acos(res: inout MGDecimal, x: MGDecimal) {
        if x.isNaN { res.setNAN(); return }
        
        var abx = x.abs //dn_abs(&abx, x);
        if abx > MGDecimal.one { res.setNAN(); return }
        
        // res = 2*atan((1-x)/sqrt(1-x*x))
        if x == MGDecimal.one {
            res = MGDecimal.zero
        } else {
            var z = x.sqr()         // dn_multiply(&z, x, x);
            z = MGDecimal.one - z     // dn_1m(&z, &z);
            z = z.sqrt()            // dn_sqrt(&z, &z);
            abx = MGDecimal.one - x   // dn_1m(&abx, x);
            z = abx / z             // dn_divide(&z, &abx, &z);
            MGDecimal.atan(res: &abx, x: z) // do_atan(&abx, &z);
            res = 2 * abx           // dn_mul2(res, &abx);
        }
    }
    
    fileprivate mutating func setNAN() {
        self.decimal.bits |= UInt8(DECNAN)
    }
    
    fileprivate mutating func setsNAN() {
        self.decimal.bits |= UInt8(DECSNAN)
    }
    
    /* Calculate sin and cos of the given number in radians.
     * We need to do some range reduction to guarantee that our Taylor series
     * converges rapidly.
     */
    public func sinCos(sinv : inout MGDecimal?, cosv : inout MGDecimal?) {
        let v = self
        if v.isSpecial { // (decNumberIsSpecial(v)) {
            sinv?.setNAN(); cosv?.setNAN()
        } else {
            let x = v % MGDecimal._2pi  // decNumberMod(&x, v, &const_2PI);
            MGDecimal.sincosTaylor(x, sout: &sinv, cout: &cosv)  // sincosTaylor(&x, sinv, cosv);
        }
    }
    
    public func sin() -> MGDecimal {
        let x = self
        var x2 = MGDecimal.zero
        var res : MGDecimal? = MGDecimal.zero
        
        if x.isSpecial {
            res!.setNAN()
        } else {
            if MGDecimal.convertToRadians(res: &x2, x: x, r0: 0, r1: 1, r2: 0, r3: 1) {
                MGDecimal.sincosTaylor(x2, sout: &res, cout: &MGDecimal.Nil)  // sincosTaylor(&x2, res, NULL);
            } else {
                res = x2  // decNumberCopy(res, &x2);
            }
        }
        return res!
    }
    
    public func cos() -> MGDecimal {
        let x = self
        var x2 = MGDecimal.zero
        var res : MGDecimal? = MGDecimal.zero
        
        if x.isSpecial {
            res!.setNAN()
        } else {
            if MGDecimal.convertToRadians(res: &x2, x: x, r0:1, r1:0, r2:1, r3:0) {
                MGDecimal.sincosTaylor(x2, sout: &MGDecimal.Nil, cout: &res)
            } else {
                res = x2  // decNumberCopy(res, &x2);
            }
        }
        return res!
    }
    
    public func tan() -> MGDecimal {
        let x = self
        var x2 = MGDecimal.zero
        var res : MGDecimal? = MGDecimal.zero
        
        if x.isSpecial {
            res!.setNAN()
        } else {
            let digits = MGDecimal.digits
            MGDecimal.digits = MGDecimal.SINCOS_DIGITS
            if MGDecimal.convertToRadians(res: &x2, x: x, r0:0, r1:MGDecimal.NaN, r2:0, r3:MGDecimal.NaN) {
                var s, c : MGDecimal?
                MGDecimal.sincosTaylor(x2, sout: &s, cout: &c)
                x2 = s! / c!  // dn_divide(&x2.n, &s.n, &c.n);
            }
            MGDecimal.digits = digits
            res = x2 + MGDecimal.zero // dn_plus(res, &x2.n);
        }
        return res!
    }
    
    public func arcSin() -> MGDecimal {
        var res = MGDecimal.zero
        MGDecimal.asin(res: &res, x: self)
        MGDecimal.convertFromRadians(res: &res, x: res)
        return res
    }
    
    public func arcCos() -> MGDecimal {
        var res = MGDecimal.zero
        MGDecimal.acos(res: &res, x: self)
        MGDecimal.convertFromRadians(res: &res, x: res)
        return res
    }
    
    public func arcTan() -> MGDecimal {
        let x = self
        var z = MGDecimal.zero
        if x.isSpecial {
            if x.isNaN {
                return MGDecimal.NaN
            } else {
                z = MGDecimal.pi_2
                if x.isNegative { z = -z }
            }
        } else {
            MGDecimal.atan(res: &z, x: x)
        }
        MGDecimal.convertFromRadians(res: &z, x: z)
        return z
    }
    
    public func arcTan2(b: MGDecimal) -> MGDecimal {
        var z = MGDecimal.atan2(y: self, x: b)
        MGDecimal.convertFromRadians(res: &z, x: z)
        return z
    }
}

//
// Hyperbolic trig functions
//

public extension MGDecimal {
    
    /* exp(x)-1 */
    private static func Expm1(_ x: MGDecimal) -> MGDecimal {
        if x.isSpecial { return x }
        let u = x.exp()
        var v = u - MGDecimal.one
        if v.isZero { return x }
        if v == -1 { return v }
        let w = v * x           // dn_multiply(&w, &v, x);
        v = u.ln()              // dn_ln(&v, &u);
        return w / v
    }
    
    /* Hyperbolic functions.
     * We start with a utility routine that calculates sinh and cosh.
     * We do the sinh as (e^x - 1) (e^x + 1) / (2 e^x) for numerical stability
     * reasons if the value of x is smallish.
     */
    private static func sinhcosh(x: MGDecimal, sinhv: inout MGDecimal?, coshv: inout MGDecimal?) {
        if sinhv != nil {
            if x.abs < 0.5 {
                var u = Expm1(x)
                let t = u / MGDecimal.two // dn_div2(&t, &u);
                u += MGDecimal.one    // dn_inc(&u);
                let v = t / u       // dn_divide(&v, &t, &u);
                u += MGDecimal.one    // dn_inc(&u);
                sinhv = u * v       // dn_multiply(sinhv, &u, &v);
            } else {
                let u = x.exp()     // dn_exp(&u, x);			// u = e^x
                let v = MGDecimal.one / u   // decNumberRecip(&v, &u);		// v = e^-x
                let t = u - v       // dn_subtract(&t, &u, &v);	// r = e^x - e^-x
                sinhv = t / MGDecimal.two       // dn_div2(sinhv, &t);
            }
        }
        if coshv != nil {
            let u = x.exp()           // dn_exp(&u, x);			// u = e^x
            let v = MGDecimal.one / u   // decNumberRecip(&v, &u);		// v = e^-x
            coshv = (u + v) / MGDecimal.two       // dn_average(coshv, &v, &u);	// r = (e^x + e^-x)/2
        }
    }
    
    public func sinh() -> MGDecimal {
        let x = self
        if x.isSpecial {
            if x.isNaN { return MGDecimal.NaN }
            return x
        }
        var res : MGDecimal? = MGDecimal.zero
        MGDecimal.sinhcosh(x: x, sinhv: &res, coshv: &MGDecimal.Nil)
        return res!
    }
    
    fileprivate mutating func setINF() {
        self.decimal.bits |= UInt8(DECINF)
    }
    
    fileprivate mutating func setNINF() {
        self.decimal.bits |= UInt8(DECNEG+DECINF)
    }
    
    public func cosh() -> MGDecimal {
        let x = self
        var res : MGDecimal? = MGDecimal.zero
        if x.isSpecial {
            if x.isNaN { return MGDecimal.NaN }
            return MGDecimal.infinity
        }
        MGDecimal.sinhcosh(x: x, sinhv: &MGDecimal.Nil, coshv: &res)
        return res!
    }
    
    public func tanh() -> MGDecimal {
        let x = self
        if x.isNaN { return MGDecimal.NaN }
        if x < 100 {
            if x.isNegative { return -1 }
            return MGDecimal.one
        }
        var a = x.sqr()               // dn_add(&a, x, x);
        let b = a.exp()-MGDecimal.one   // decNumberExpm1(&b, &a);
        a = b + MGDecimal.two           // dn_p2(&a, &b);
        return b / a
    }
    
    /* ln(1+x) */
    private func Ln1p() -> MGDecimal {
        let x = self
        if x.isSpecial || x.isZero {
            return x
        }
        let u = x + MGDecimal.one
        var v = u - MGDecimal.one
        if v == 0 { return x }
        let w = x / v // dn_divide(&w, x, &v);
        v = u.ln()
        return v * w
    }
    
    public func arcSinh() -> MGDecimal {
        let x = self
        var y = x.sqr()             // decNumberSquare(&y, x);		// y = x^2
        var z = y + MGDecimal.one     // dn_p1(&z, &y);			// z = x^2 + 1
        y = z.sqrt() + MGDecimal.one  // dn_sqrt(&y, &z);		// y = sqrt(x^2+1)
        z = x / y + MGDecimal.one     // dn_divide(&z, x, &y);
        y = x * z                   // dn_multiply(&y, x, &z);
        return y.Ln1p()
    }
    
    
    public func arcCosh() -> MGDecimal {
        let x = self
        var res = x.sqr()           // decNumberSquare(res, x);	// r = x^2
        var z = res - MGDecimal.one   // dn_m1(&z, res);			// z = x^2 + 1
        res = z.sqr()               // dn_sqrt(res, &z);		// r = sqrt(x^2+1)
        z = res + x                 // dn_add(&z, res, x);		// z = x + sqrt(x^2+1)
        return z.ln()
    }
    
    public func arcTanh() -> MGDecimal {
        let x = self
        var res = MGDecimal.zero
        if x.isNaN { return MGDecimal.NaN }
        var y = x.abs
        if y == MGDecimal.one {
            if x.isNegative { res.setNINF(); return res }
            return MGDecimal.infinity
        }
        // Not the obvious formula but more stable...
        var z = x - MGDecimal.one   // dn_1m(&z, x);
        y = x / z                 // dn_divide(&y, x, &z);
        z = MGDecimal.two * y       // dn_mul2(&z, &y);
        y = z.Ln1p()              // decNumberLn1p(&y, &z);
        return y / MGDecimal.two
    }

}

//
// Combination/Permutation functions
//

public extension MGDecimal {
    
    /* Calculate permutations:
     * C(x, y) = P(x, y) / y! = x! / ( (x-y)! y! )
     */
    public func comb (y: MGDecimal) -> MGDecimal {
        return self.perm(y: y) / y.factorial()
    }
    
    /* Calculate permutations:
     * P(x, y) = x! / (x-y)!
     */
    public func perm (y: MGDecimal) -> MGDecimal {
        let xfact = self.factorial()
        return xfact / (self - y).factorial()
    }
    
    public func gamma () -> MGDecimal {
        let t = self
        let ndp = Double(MGDecimal.digits)
        
        let working_prec = ceil(1.5 * ndp)
        MGDecimal.digits = Int(working_prec)
        
        print("t = \(t)")
        let a = ceil( 1.25 * ndp / Darwin.log10( 2.0 * Darwin.acos(-1.0) ) )
        
        // Handle improper arguments.
        if t.abs > 1.0e8 {
            print("gamma: argument is too large")
            return MGDecimal.infinity
        } else if t.isInteger && t <= 0 {
            print("gamma: invalid negative argument")
            return MGDecimal.NaN
        }
        
        // for testing first handle args greater than 1/2
        // expand with branch later.
        var arg : MGDecimal
        
        if t < 0.5 {
            arg = 1.0 - t
            
            // divide by zero trap for later compuation of cosecant
            if (MGDecimal.pi * t).sin() == 0 {
                print("value of argument is too close to a negative integer or zero.\n" +
                    "sin(pi * t) is zero indicating singularity. Increase precision to fix. ")
                return MGDecimal.infinity
            }
        } else {
            arg = t
            
            // quick exit with factorial if integer
            if t.isInteger {
                var temp : MGDecimal = MGDecimal.one
                for k in 2..<t.int {
                    temp *= MGDecimal(k)
                }
                return temp
            }
        }
        
        let N = a - 1
        var sign = -1
        
        let rootTwoPi = MGDecimal._2pi.sqrt()
        let oneOverRootTwoPi = MGDecimal.one / rootTwoPi
        
        let e = MGDecimal.one.exp()
        let oneOverE = MGDecimal.one / e
        let x = MGDecimal(floatLiteral: a)
        var runningExp = x.exp()
        var runningFactorial = MGDecimal.one
        
        var sum = MGDecimal.one
        
//        print("x = \(x), runningExp = \(runningExp), runningFactorial = \(runningFactorial)")
        
        // get summation term
        for k in 1...Int(N) {
            sign = -sign
            
            // keep (k-1)! term for computing coefficient
            if k == 1 {
                runningFactorial = MGDecimal.one
            } else {
                runningFactorial *= MGDecimal(k-1)
            }
            
            runningExp *= oneOverE   // e ^ (a-k). divide by factor of e each iteration
            
            let x1 = MGDecimal(floatLiteral: a - Double(k) )
            let x2 = MGDecimal(floatLiteral: Double(k) - 0.5)
            
            sum += oneOverRootTwoPi * MGDecimal(sign) * runningExp * x1 ** x2 / ( runningFactorial * (arg + MGDecimal(k - 1) ))
//            print("Iteration \(k), sum = \(sum)")
        }
        
        // restore the original precision 
        MGDecimal.digits = Int(ndp)
        
        // compute using the identity
        let da = MGDecimal(floatLiteral: a)
        let arga1 = arg + da - 1
        let arga2 = -arg - da + 1
        if t < 0.5 {
            let temp = rootTwoPi * arga1 ** (arg - 0.5) * arga2.exp() * sum
            return MGDecimal.pi / ((MGDecimal.pi * t).sin() * temp)
        }
        
        return rootTwoPi * arga1 ** (arg - 0.5) * arga2.exp() * sum
    }
    
    public func factorial () -> MGDecimal {
        let x = self + MGDecimal.one
        return x.gamma()
    }
    
}

extension MGDecimal : SignedNumeric {
    
    public typealias Magnitude = MGDecimal
    public var magnitude : MGDecimal { return self.abs }
    
    public init?<T>(exactly source: T) where T : BinaryInteger {
        self.init(Int(source))
    }
    
    public static func * (lhs: MGDecimal, rhs: MGDecimal) -> MGDecimal { return lhs.mul(rhs) }
    public static func *= (lhs: inout MGDecimal, rhs: MGDecimal) { lhs = lhs.mul(rhs) }
    public static prefix func + (lhs: MGDecimal) -> MGDecimal { return lhs }
    public static func + (lhs: MGDecimal, rhs: MGDecimal) -> MGDecimal { return lhs.add(rhs) }
    public static func += (lhs: inout MGDecimal, rhs: MGDecimal) { lhs = lhs.add(rhs) }
//    public static func - (lhs: Decimal, rhs: Decimal) -> Decimal { return lhs.sub(rhs) }
    public static func -= (lhs: inout MGDecimal, rhs: MGDecimal) { lhs = lhs.sub(rhs) }

}

//
// Support the print() command.
//

extension MGDecimal : CustomStringConvertible {
    
    public var description : String  {
        var cs = [CChar](repeating: 0, count: Int(decimal.digits+14))
        var local = decimal
        decNumberToString(&local, &cs)
        return String(cString: &cs)
    }
    
}

//
// Comparison and equality operator definitions
//

extension MGDecimal : Comparable {
    
    public func cmp (_ b: MGDecimal) -> ComparisonResult {
        var b = b
        var a = decimal
        var result = decNumber()
        decNumberCompare(&result, &a, &b.decimal, &MGDecimal.context)
        let ai = decNumberToInt32(&result, &MGDecimal.context)
        switch ai {
        case -1: return .orderedAscending
        case 0:  return .orderedSame
        default: return .orderedDescending
        }
    }
    
    static public func == (lhs: MGDecimal, rhs: MGDecimal) -> Bool {
        return lhs.cmp(rhs) == .orderedSame
    }
    
    static public func < (lhs: MGDecimal, rhs: MGDecimal) -> Bool {
        return lhs.cmp(rhs) == .orderedAscending
    }
    
}

//
// Allows things like -> a : Decimal = 12345
//

extension MGDecimal : ExpressibleByIntegerLiteral {

    public init(integerLiteral value: Int) { self.init(value) }
    
}

//
// Allows things like -> a : [Decimal] = [1.2, 3.4, 5.67]
// Note: These conversions are not guaranteed to be exact.
//

extension MGDecimal : ExpressibleByFloatLiteral {
    
    public init(floatLiteral value: Double) { self.init(String(value))! }  // not exactly representable anyway so we cheat
    
}

//
// Allows things like -> a : Set<Decimal> = [12.4, 15, 100]
//

extension MGDecimal : Hashable {
    
    public var hashValue : Int {
        return description.hashValue   // probably not very fast but not used much anyway
    }
    
}

//
// Allows things like -> a : Decimal = "12345"
//

extension MGDecimal : ExpressibleByStringLiteral {
    
    public typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
    public typealias UnicodeScalarLiteralType = Character
    public init (stringLiteral s: String) { self.init(s)! }
    public init (extendedGraphemeClusterLiteral s: ExtendedGraphemeClusterLiteralType) { self.init(stringLiteral:s) }
    public init (unicodeScalarLiteral s: UnicodeScalarLiteralType) { self.init(stringLiteral:"\(s)") }
    
}

//
// Convenience functions
//

public extension MGDecimal {
    
    public func sqr() -> MGDecimal { return self * self }
    public var ² : MGDecimal { return sqr() }
    
}

public extension MGDecimal {
    
    // MARK: - Archival Operations
    
    static var UInt8Type = "C".cString(using: String.Encoding.ascii)!
    static var Int32Type = "l".cString(using: String.Encoding.ascii)!
    
    public init? (coder: NSCoder) {
        var scale : Int32 = 0
        var size : Int32 = 0
        coder.decodeValue(ofObjCType: &MGDecimal.Int32Type, at: &size)
        coder.decodeValue(ofObjCType: &MGDecimal.Int32Type, at: &scale)
        var bytes = [UInt8](repeating: 0, count: Int(size))
        coder.decodeArray(ofObjCType: &MGDecimal.UInt8Type, count: Int(size), at: &bytes)
        decPackedToNumber(&bytes, Int32(size), &scale, &decimal)
    }
    
    public func encode(with coder: NSCoder) {
        var local = decimal
        var scale : Int32 = 0
        var size = decimal.digits/2+1
        var bytes = [UInt8](repeating: 0, count: Int(size))
        decPackedFromNumber(&bytes, size, &scale, &local)
        coder.encodeValue(ofObjCType: &MGDecimal.Int32Type, at: &size)
        coder.encodeValue(ofObjCType: &MGDecimal.Int32Type, at: &scale)
        coder.encodeArray(ofObjCType: &MGDecimal.UInt8Type, count: Int(size), at: &bytes)
    }
    
}

//
// Declaration of the power (**) operator
//

infix operator ** : ExponentPrecedence
infix operator **= : ExponentPrecedence
precedencegroup ExponentPrecedence {
    associativity: left
    higherThan: MultiplicationPrecedence
}

//
// Mathematical operator definitions
//

public extension MGDecimal {
    
    static public func % (lhs: MGDecimal, rhs: MGDecimal) -> MGDecimal { return lhs.remainder(rhs) }
//    static public func * (lhs: Decimal, rhs: Decimal) -> Decimal { return lhs.mul(rhs) }
//    static public func + (lhs: Decimal, rhs: Decimal) -> Decimal { return lhs.add(rhs) }
    static public func / (lhs: MGDecimal, rhs: MGDecimal) -> MGDecimal { return lhs.div(rhs) }
//    static public prefix func + (a: Decimal) -> Decimal { return a }
    
//    static public func -= (a: inout Decimal, b: Decimal) { a = a - b }
//    static public func += (a: inout Decimal, b: Decimal) { a = a + b }
//    static public func *= (a: inout Decimal, b: Decimal) { a = a * b }
    static public func /= (a: inout MGDecimal, b: MGDecimal) { a = a / b }
    static public func %= (a: inout MGDecimal, b: MGDecimal) { a = a % b }
    static public func **= (a: inout MGDecimal, b: MGDecimal) { a = a ** b }
    
    static public func ** (base: MGDecimal, power: Int) -> MGDecimal { return base ** MGDecimal(power) }
    static public func ** (base: Int, power: MGDecimal) -> MGDecimal { return MGDecimal(base) ** power }
    static public func ** (base: MGDecimal, power: MGDecimal) -> MGDecimal { return base.pow(power) }
    
    //
    // Logical operators
    //
    
    static public func & (a: MGDecimal, b: MGDecimal) -> MGDecimal { return a.and(b) }
    static public func | (a: MGDecimal, b: MGDecimal) -> MGDecimal { return a.or(b) }
    static public func ^ (a: MGDecimal, b: MGDecimal) -> MGDecimal { return a.xor(b) }
    static public prefix func ~ (a: MGDecimal) -> MGDecimal { return a.not() }
    
    static public func &= (a: inout MGDecimal, b: MGDecimal) { a = a & b }
    static public func |= (a: inout MGDecimal, b: MGDecimal) { a = a | b }
    static public func ^= (a: inout MGDecimal, b: MGDecimal) { a = a ^ b }
    
    static public func << (a: MGDecimal, b: MGDecimal) -> MGDecimal { return a.shift(b.abs) }
    static public func >> (a: MGDecimal, b: MGDecimal) -> MGDecimal { return a.shift(-b.abs) }
    
}

