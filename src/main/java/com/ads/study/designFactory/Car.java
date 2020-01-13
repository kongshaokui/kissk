package com.ads.study.designFactory;

/**
 * @Classname Duck
 * @Description TODO
 * @Created by kongshaokui
 * @Date 2019/9/24 16:16
 */

/**
 * 汽车
 */
public class Car implements ToyInterface{

    @Override
    public String cry() {
        return "呜呜呜";
    }
}
