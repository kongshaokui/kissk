package com.ads.study.designFactory;

/**
 *  工厂接口
 */
public interface FactoryInterface {
    /**
     * 获取对应的玩具实例对象
     * @return
     */
    ToyInterface newToy();
}
