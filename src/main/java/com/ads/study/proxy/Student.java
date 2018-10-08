package com.ads.study.proxy;

/**
 * 被代理类
 * User: kismetkong@tcl.com
 * Date: 2018-09-25
 * Time: 10:27
 */
public class Student implements Person{

    private String name;

    private int age;

    public Student(String name) {
        this.name = name;
    }

    public Student(String name, int age) {
        this.name = name;
        this.age = age;
    }

    @Override
    public void setMoney() {
        System.out.println(name+"交学费");
    }

    public int getAge() {
        return age;
    }

    public void setAge(int age) {
        this.age = age;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }
}
