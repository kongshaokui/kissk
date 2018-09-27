package com.ads.study.designPattern.strategy;

import com.ads.study.designPattern.strategy.duckInterface.CallInterface;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-05-23
 * Time: 17:11
 */
public class CallGuaGuaImpl implements CallInterface {

    @Override
    public void call() {
        System.out.println("我是只会呱呱叫的鸭子");
    }
}
