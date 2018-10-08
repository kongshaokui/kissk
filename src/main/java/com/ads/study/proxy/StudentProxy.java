package com.ads.study.proxy;

/**
 * 简单的静态代理-代理类
 * User: kismetkong@tcl.com
 * Date: 2018-09-25
 * Time: 10:31
 */
public class StudentProxy implements Person{

    private Student student;

    public StudentProxy(Student student) {
        if(student.getClass()==Student.class){
            this.student=student;
        }
    }

    @Override
    public void setMoney() {
        student.setMoney();
    }

    public static void main(String[] args){
//        StudentProxy studentProxy = new StudentProxy(new Student("李斯"));
//        studentProxy.setMoney();
    }

}

