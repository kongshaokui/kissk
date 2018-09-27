package com.ads.study.proxy;

import java.lang.reflect.InvocationHandler;
import java.lang.reflect.Method;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-09-25
 * Time: 15:10
 */
public class MyInvocationHandler<T> implements InvocationHandler{

    T target;

    public MyInvocationHandler(T target) {
        this.target = target;
    }

    @Override
    public Object invoke(Object proxy, Method method, Object[] args) throws Throwable {
        System.out.println("代理执行...");
        Object invoke = method.invoke(target, args);
        System.out.println("代理执行结束...");
        return invoke;
    }
}
