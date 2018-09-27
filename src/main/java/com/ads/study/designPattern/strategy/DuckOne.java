package com.ads.study.designPattern.strategy;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-05-23
 * Time: 17:18
 */
public class DuckOne extends Duck{

    public DuckOne(){
        callInterface=new CallGuaGuaImpl();
        flyInterface=new FlyNoImpl();
    }


    public static void main(String[] args) {
        DuckOne duck = new DuckOne();
//        CallGuaGuaImpl callGuaGua = new CallGuaGuaImpl();
//        FlyNoImpl flyNo = new FlyNoImpl();

//        duck.setCallInterface(callGuaGua);
//        duck.setFlyInterface(flyNo);
        duck.fly();
        duck.call();
    }

}
