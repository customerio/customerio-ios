import Common
import Foundation

/*
 Contains public aliases to expose public structures from the 'Common' module
 to the 'Tracking' module. The goal is that customers do not need to import
 the 'Common' module in their code. But, some data structures need to exist
 in 'Common' as they are used in the 'Common' code.
 */

public typealias Region = Common.Region
public typealias CioLogLevel = Common.CioLogLevel
