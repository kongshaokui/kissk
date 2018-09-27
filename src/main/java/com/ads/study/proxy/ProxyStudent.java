package com.ads.study.proxy;

import javassist.util.proxy.ProxyFactory;

import java.io.ObjectInputStream;
import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Proxy;

/**
 * 动态代理 实现
 * User: kismetkong@tcl.com
 * Date: 2018-09-25
 * Time: 10:51
 */
public class ProxyStudent{


    public static void main(String[] args){

        Student student = new Student("张三");

        InvocationHandler stu = new MyInvocationHandler<>(student);

        Person proxy = (Person)Proxy.newProxyInstance(Person.class.getClassLoader(), new Class<?>[]{Person.class},
                stu);
        proxy.setMoney();



    }

}
