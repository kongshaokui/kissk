package com.ads.study.designFactory;

/**
 * @Classname CarFactory
 * @Description TODO
 * @Created by kongshaokui
 * @Date 2019/9/25 11:27
 */
public class DuckFactory implements FactoryInterface{
    public ToyInterface newToy() {
        /**
         * 在这里编写其他业务逻辑代码
         */
        return new Duck();
    }
}
