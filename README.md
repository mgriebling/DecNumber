# DecNumber
A Swift-friendly interface to the C-based decNumber library.  This library can be built either for iOS or OSX.  See also the DecNumbers repository if you prefer the bare metal C interface.

This library introduces two Swift data types: MGDecimal, an arbitrary-precision decimal number based on the decNumber library and ComplexDec, an imaginary number data type built on the MGDecimal decimal number type.  Both numeric types have the basic functions but the ComplexDec includes more mathematical functions.  The complex type is built on work by Dan Kogai.  I have extended his rudimentary complex functions to provide string conversions and more mathematical routines.
