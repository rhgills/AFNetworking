#if DEBUG
#define PROPERTY(propName)    NSStringFromSelector(@selector(propName))
#else
#define PROPERTY(propName)    @#propName
#endif

//extern NSString * const RHGUnimplementedAbstractMethodException;
//#define ABSTRACT_METHOD [NSException raise:RHGUnimplementedAbstractMethodException format:@"Abstract method %@ must be implemented in a concrete subclass. Don't call super.", NSStringFromSelector(_cmd)];
