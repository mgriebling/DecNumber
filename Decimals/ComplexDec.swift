//
//  ComplexDec.swift
//
//  This ComplexDec type provides functions and operators that work
//  with imaginary numbers.  It is based on the MGDecimal type.
//  I have extended the MGDecimal type to be RealType/FloatingPoint
//  protocol conformant to satisfy the Complex generic type declarations.
//  This allows all the complex algorithms to be reused by any numeric
//  type that conforms to the RealType protocol.
//
//  You may use this library for personal use only.  There are no guarantees of
//  functionality for a given purpose.  If you do fix bugs, I'd appreciate getting
//  updates of the fixed source.
//
//  I have added FloatingPoint protocol conformance to make the MGDecimal
//  a legitimate Apple-compatible floating point number type.  Unfortunately,
//  more functions are needed to provide the functions that I required than
//  are provided by the FloatingPoint protocol so a secondary RealType protocol
//  is also used.  I don't believe complex numbers can satisfy the FloatingPoint
//  protocol so this functionality is not currently implemented.  For example,
//  complex comparisons and strides are not possible.
//
//  Created by Mike Griebling on 30 Jul 2017.
//  Copyright © 2017-2018 Solinst Canada. All rights reserved.
//

import Foundation

extension MGDecimal : RealType {

    public static func - (_ a: MGDecimal, _ b: MGDecimal) -> MGDecimal { return a.sub(b) }
    public static prefix func - (_ a: MGDecimal) -> MGDecimal { return a.negate() }
    
    public func atan2(_ y: MGDecimal) -> MGDecimal { return self.arcTan2(b:y) }
    public func hypot(_ arg: MGDecimal) -> MGDecimal { return self.hypot(y:arg) }

    public var isSignaling: Bool { return self.isSpecial }
    public var isNormal: Bool    { return self.isNormal }
    public var isSignMinus: Bool { return self.isNegative }

    public init?(_ value: String) { self.init(value, digits: MGDecimal.digits, radix: 10) }
    public init(_ value: Float)   { self.init(value) }
    public init(_ value: Double)  { self.init(value) }
    public init(_ value: Int64)   { self.init(Int(value)) }
    public init(_ value: UInt64)  { self.init(UInt(value)) }
    public init(_ value: Int32)   { self.init(Int(value)) }
    public init(_ value: UInt32)  { self.init(UInt(value)) }
    public init(_ value: Int16)   { self.init(Int(value)) }
    public init(_ value: UInt16)  { self.init(UInt(value)) }
    public init(_ value: Int8)    { self.init(Int(value)) }
    public init(_ value: UInt8)   { self.init(UInt(value)) }
    
}

extension MGDecimal : Strideable {
    
    public func distance(to other: MGDecimal) -> MGDecimal.Stride { return self.sub(other) }
    public func advanced(by n: MGDecimal.Stride) -> MGDecimal { return self.add(n) }
    public typealias Stride = MGDecimal
    
}

extension MGDecimal : FloatingPoint {

    public static var nan: MGDecimal { return MGDecimal.NaN }
    public static var signalingNaN: MGDecimal { return MGDecimal.sNaN }
    
    public var ulp: MGDecimal { return self.eps }
    
    public static var leastNonzeroMagnitude: MGDecimal { return leastNormalMagnitude }
    
    public var sign: FloatingPointSign { if self.isNegative { return .minus } else { return .plus } }
    
    public mutating func formSquareRoot() { self = self.sqrt() }
    public mutating func addProduct(_ lhs: MGDecimal, _ rhs: MGDecimal) { self = self.mulAcc(lhs, c: rhs) }
    
    public func isEqual(to other: MGDecimal) -> Bool { return self.cmp(other) == .orderedSame }
    public func isLess(than other: MGDecimal) -> Bool { return self.cmp(other) == .orderedAscending }
    public func isLessThanOrEqualTo(_ other: MGDecimal) -> Bool {
        let result = self.cmp(other)
        return result == .orderedSame || result == .orderedAscending
    }
    
    public var isSignalingNaN: Bool { return self.floatingPointClass == .signalingNaN }
   
}

public typealias ComplexDec = Complex<MGDecimal>


