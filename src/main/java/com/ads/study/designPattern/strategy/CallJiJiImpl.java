package com.ads.study.designPattern.strategy;

import com.ads.study.designPattern.strategy.duckInterface.CallInterface;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-05-23
 * Time: 17:14
 */
public class CallJiJiImpl implements CallInterface {

    @Override
    public void call() {
        System.out.println("我是只唧唧叫的鸭子");
    }
}
