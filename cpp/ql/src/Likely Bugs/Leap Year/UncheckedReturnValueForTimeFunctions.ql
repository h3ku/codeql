/**
 * @name Year field changed using an arithmetic operation is used on an unchecked time conversion function
 * @description A year field changed using an arithmetic operation is used on a time conversion function, but the return value of the function is not checked for success or failure
 * @kind problem
 * @problem.severity error
 * @id cpp/leap-year/unchecked-return-value-for-time-conversion-function
 * @precision high
 * @tags security
 *       leap-year
 */

import cpp
import LeapYear

/**
 * A YearFieldAccess that is modifying the year by any arithmetic operation
 * 
 * NOTE:
 * To change this class to work for general purpose date transformations that do not check the return value,
 * make the following changes:
 *  -> extends FieldAccess (line 27) 
 *  -> this.isModified (line 33)
 * Expect a lower precision for a general purpose version.
 */

class DateStructModifiedFieldAccess extends LeapYearFieldAccess {
   DateStructModifiedFieldAccess() {
    exists( Field f, StructLikeClass struct |
       f.getAnAccess() = this
       and struct.getAField() = f
       and struct.getUnderlyingType() instanceof DateDataStruct
       and this.isModifiedByArithmeticOperation()
  	 )
  }
}

/**
 * This is a list of APIs that will get the system time, and therefore guarantee that the value is valid
 */
class SafeTimeGatheringFunction extends Function {
  SafeTimeGatheringFunction() {
    this.getQualifiedName().matches("GetFileTime")
    or this.getQualifiedName().matches("GetSystemTime")
    or this.getQualifiedName().matches("NtQuerySystemTime")
  }
}

/**
 * This list of APIs should check for the return value to detect problems during the conversion
 */
class TimeConversionFunction extends Function {
  TimeConversionFunction() {
    this.getQualifiedName().matches("FileTimeToSystemTime")
    or this.getQualifiedName().matches("SystemTimeToFileTime")
    or this.getQualifiedName().matches("SystemTimeToTzSpecificLocalTime")
    or this.getQualifiedName().matches("SystemTimeToTzSpecificLocalTimeEx")
    or this.getQualifiedName().matches("TzSpecificLocalTimeToSystemTime")
    or this.getQualifiedName().matches("TzSpecificLocalTimeToSystemTimeEx")
    or this.getQualifiedName().matches("RtlLocalTimeToSystemTime")
    or this.getQualifiedName().matches("RtlTimeToSecondsSince1970")
    or this.getQualifiedName().matches("_mkgmtime")
  }
}

from FunctionCall fcall, TimeConversionFunction trf
  , Variable var
where fcall = trf.getACallToThisFunction()
  and fcall instanceof ExprInVoidContext
  and var.getUnderlyingType() instanceof DateDataStruct
  and (exists(AddressOfExpr aoe | 
       aoe = fcall.getAnArgument()
       and aoe.getAddressable() = var 
    ) or exists(VariableAccess va |
      fcall.getAnArgument() = va
      and var.getAnAccess() = va
    )
  )
  and exists(DateStructModifiedFieldAccess dsmfa, VariableAccess modifiedVarAccess |
    modifiedVarAccess = var.getAnAccess() 
    and modifiedVarAccess  = dsmfa.getQualifier()
    and modifiedVarAccess = fcall.getAPredecessor*()
  )
  // Remove false positives
  and not (
    // Remove any instance where the predecessor is a SafeTimeGatheringFunction and no change to the data happened in between
    exists(FunctionCall pred |
      pred = fcall.getAPredecessor*()
      and exists( SafeTimeGatheringFunction stgf | 
      pred = stgf.getACallToThisFunction()
    )
    and not exists(DateStructModifiedFieldAccess dsmfa, VariableAccess modifiedVarAccess |
      modifiedVarAccess = var.getAnAccess() 
      and modifiedVarAccess  = dsmfa.getQualifier()
      and modifiedVarAccess = fcall.getAPredecessor*()
      and modifiedVarAccess = pred.getASuccessor*()
    )
  )
  // Remove any instance where the year is changed, but the month is set to 1 (year wrapping)
  or exists(MonthFieldAccess  mfa, AssignExpr ae |
       mfa.getQualifier() = var.getAnAccess()
       and mfa.isModified()
       and mfa = fcall.getAPredecessor*()
       and ae = mfa.getEnclosingElement()
       and ae.getAnOperand().getValue().toInt() = 1 
     )
  )
select fcall, "Return value of $@ function should be verified to check for any error because variable $@ is not guaranteed to be safe.", trf, trf.getQualifiedName().toString(), var, var.getName()