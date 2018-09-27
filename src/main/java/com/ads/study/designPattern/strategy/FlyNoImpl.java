package com.ads.study.designPattern.strategy;

import com.ads.study.designPattern.strategy.duckInterface.FlyInterface;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-05-23
 * Time: 17:24
 */
public class FlyNoImpl implements FlyInterface{
    @Override
    public void fly() {
        System.out.println("我是只旱鸭子");
    }
}
