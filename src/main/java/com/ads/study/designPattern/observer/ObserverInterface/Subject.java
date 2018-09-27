package com.ads.study.designPattern.observer.ObserverInterface;

/**
 * 主题对象接口
 * User: kismetkong@tcl.com
 * Date: 2018-06-08
 * Time: 15:50
 */
public interface Subject {

    /**
     * 注册
     * @param o
     */
    public void registerObserver(Observer o);

    /**
     * 注销
     * @param o
     */
    public void removeObserver(Observer o);

    /**
     * 通知
     */
    public void notifyObservers();

}
