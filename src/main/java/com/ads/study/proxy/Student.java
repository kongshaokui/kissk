package com.ads.study.proxy;

/**
 * 被代理类
 * User: kismetkong@tcl.com
 * Date: 2018-09-25
 * Time: 10:27
 */
public class Student implements Person{

    private String name;

    public Student(String name) {
        this.name = name;
    }

    @Override
    public void setMoney() {
        System.out.println(name+"交学费");
    }
}
