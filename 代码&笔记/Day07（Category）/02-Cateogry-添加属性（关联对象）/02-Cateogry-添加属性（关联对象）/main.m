//
//  main.m
//  01-Cateogry-load
//
//  Created by 周健平 on 2019/10/26.
//  Copyright © 2019 周健平. All rights reserved.
//
//  问题1：可以给类/元类对象添加关联对象吗？
// 【可以】，只要是个对象，都可以使用objc_setAssociatedObject添加关联对象
//  但是，由于类/元类对象是唯一的，所以添加的这个关联对象是共用的
//
//  问题2：分类添加的属性，是不是也会在这个类里面添加了这个成员变量？
// 【不会】，不能给对象添加新的成员变量，又因为分类底层结构的限制，也不能添加成员变量到分类中
//  实际上这不是真正的属性，而是关联对象，关联对象不是存储在这个对象里面，不会影响这个对象原来的内存结构
//  关联对象是存储在全局的、统一的一个AssociationsManager中
//
//  问题3：关联对象会强引用对象吗？
// 【不会】，从源码可以看出，对象只是用来获取key（DISGUISE(object)），通过这个key来获取对应的哈希表。
//  同理，对象也没有强引用关联对象，两者的关联是由AssociationsManager来管理
//  当对象即将销毁时，AssociationsManager会擦除这个对象的所有关联对象

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "JPPerson.h"
#import "JPPerson+JPTest1.h"

// extern：表示变量或者函数的定义可能在别的文件中，提示编译器遇到此变量或者函数时，在别的文件里寻找其定义。
extern const void *JPTestKey;
extern const void *JPNameKey;

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // insert code here...
        NSLog(@"Hello, World!");
        
        NSLog(@"指针的内存大小 %zd", sizeof(void *)); // 8
        NSLog(@"int的内存大小 %zd", sizeof(int)); // 4
        NSLog(@"char的内存大小 %zd", sizeof(char)); // 1
        NSLog(@"SEL的内存大小 %zd", sizeof(SEL)); // 8 也是指针
        
        NSLog(@"外部访问JPTestKey --- %p", JPTestKey);
        
        JPPerson *per1 = [[JPPerson alloc] init];
        per1.age = 27;
        per1.name = @"shuaigepinng";
        per1.weight = 160;
        per1.height = 177;
        NSLog(@"per1 age is %d, name is %@, weight is %d, height is %d", per1.age, per1.name, per1.weight, per1.height);
        
        JPPerson *per2 = [[JPPerson alloc] init];
        per2.age = 25;
        per2.name = @"shadou";
        per2.weight = 105;
        per2.height = 162;
        NSLog(@"per2 age is %d, name is %@, weight is %d, height is %d", per2.age, per2.name, per2.weight, per2.height);
        
        // 注意：关联对象没有弱引用的存储策略（毕竟不是属性，只是Runtime的一种API）
        {
            JPPerson *tmpPer = [[JPPerson alloc] init];
            objc_setAssociatedObject(per2, @"tmpPer", tmpPer, OBJC_ASSOCIATION_ASSIGN);
            
            // PS：调用NSLog或重写dealloc相关使用到临时对象的方法，可能会导致这个临时对象并不会在{}之后立即销毁。
        }
        // assign引用，不会强引用{}里面创建的tmpPer，因此{}之后tmpPer就被销毁了
        // 但由于不是weak引用，这个指针并不会自动置空，还是存储着之前tmpPer的地址值
        // 所以{}之后再访问这个地址就会造成【坏内存访问】
        JPPerson *tmpPer = objc_getAssociatedObject(per2, @"tmpPer");
        NSLog(@"tmpPer死后再访问会崩溃！ %p", tmpPer);
    }
}

/*
 
 关联对象的原理：
    · 关联对象并不是存储在被关联对象本身内存中
    · 关联对象存储在全局的、统一的一个AssociationsManager中
    · 设置关联对象为nil，就相当于【移除】关联对象
     （如int这种基本数据类型实际会被包装成NSNumber类型，移除这种就不是置0，而是置nil）
 
 实现关联对象技术的核心对象：
    · AssociationsManager // 操作表的管理者
    · AssociationsHashMap // <对象, ObjectAssociationMap>
    · ObjectAssociationMap // <key, ObjcAssociation>
    · ObjcAssociation // <存储策略, 值>
 例：objc_setAssociatedObject(self, &JPNameKey, name, OBJC_ASSOCIATION_COPY_NONATOMIC);
 AssociationsManager
    → AssociationsHashMap <DISGUISE(self), ObjectAssociationMap>
        → ObjectAssociationMap <&JPNameKey, ObjcAssociation>
            → ObjcAssociation <OBJC_ASSOCIATION_COPY_NONATOMIC, name>

 Runtime底层实现：
 
 objc_setAssociatedObject(id object, const void *key, id value, objc_AssociationPolicy policy)
 ↓
 _object_set_associative_reference(object, (void *)key, value, policy)
 ↓
 AssociationsManager
    → AssociationsHashMap <disguised_ptr_t, ObjectAssociationMap>
        → ObjectAssociationMap <void *, ObjcAssociation>
            → ObjcAssociation <uintptr_t _policy, id _value>
 
 AssociationsManager：
 class AssociationsManager {
     static AssociationsHashMap *_map;
     ...
 };
 ↓
 AssociationsHashMap：
 class AssociationsHashMap : public unordered_map<disguised_ptr_t, ObjectAssociationMap *, DisguisedPointerHash, DisguisedPointerEqual, AssociationsHashMapAllocator> {
     ...
 };
 // AssociationsHashMap 继承于 unordered_map
 // 其中disguised_ptr_t为Key，ObjectAssociationMap为value，而ObjectAssociationMap也是一个map
 ↓
 ObjectAssociationMap：
 class ObjectAssociationMap : public std::map<void *, ObjcAssociation, ObjectPointerLess, ObjectAssociationMapAllocator> {
     ...
 };
 // 其中void *为Key，ObjcAssociation为value
 ↓
 ObjcAssociation：
 class ObjcAssociation {
     uintptr_t _policy;
     id _value;
     ...
 };
 // 可以看到objc_setAssociatedObject传的value和policy（属性存储策略）都被存到ObjcAssociation里面
 
 */
