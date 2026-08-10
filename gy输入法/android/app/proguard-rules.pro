# T0：release 未启用混淆（见 app/build.gradle.kts）。
# 启用混淆前必须补齐：JNI 侧类/方法 keep 规则、InputMethodService 子类 keep、
# 以及 Rime 数据路径相关的资源收缩白名单。
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
