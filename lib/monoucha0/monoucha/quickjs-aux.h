#define toJSValueConst(x) (x)
#define toJSValueConstArray(x) (x)

void cha_jsDestroyImpl(void **);
void cha_jsSinkImpl(void **, void *);
void cha_jsCopyImpl(void **, void *);
void *cha_jsDup(void *);

#define cha_jsDestroy(x) cha_jsDestroyImpl((void **)x)
#define cha_jsSink(x, y) cha_jsSinkImpl((void **)x, y)
#define cha_jsCopy(x, y) cha_jsCopyImpl((void **)x, y)

#define cha_dotGet(x) (x)
#define cha_jsSinkIntoEther(x) ((void)0)
