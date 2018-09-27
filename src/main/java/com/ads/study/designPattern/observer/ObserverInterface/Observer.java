package com.ads.study.designPattern.observer.ObserverInterface;

/**
 * 观察者对象接口
 * User: kismetkong@tcl.com
 * Date: 2018-06-08
 * Time: 16:25
 */
public interface Observer {

    /**
     * 提供给主题 通知观察值数据变更
     */
    public void update(String humidity);


}
