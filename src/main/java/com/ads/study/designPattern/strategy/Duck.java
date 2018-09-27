package com.ads.study.designPattern.strategy;

import com.ads.study.designPattern.strategy.duckInterface.CallInterface;
import com.ads.study.designPattern.strategy.duckInterface.FlyInterface;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-05-23
 * Time: 17:15
 */
public class Duck {



    CallInterface callInterface;

    FlyInterface flyInterface;


    public Duck(){
    }

    public void mouth(){
        System.out.println("嘴巴扁扁");
    }

    public void eye(){
        System.out.println("眼镜圆圆");
    }

    public void setCallInterface(CallInterface callInterface){
        this.callInterface=callInterface;
    }

    public void setFlyInterface(FlyInterface flyInterface){
        this.flyInterface=flyInterface;
    }

    public void fly(){
        flyInterface.fly();
    }

    public void call(){
        callInterface.call();
    }
}
