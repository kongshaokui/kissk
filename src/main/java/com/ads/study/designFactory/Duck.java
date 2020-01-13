package com.ads.study.designFactory;

/**
 * @Classname Duck
 * @Description TODO
 * @Created by kongshaokui
 * @Date 2019/9/24 16:16
 */

/**
 * 鸭子
 */
public class Duck implements ToyInterface{

    @Override
    public String cry() {
        return "呱呱呱";
    }
}
