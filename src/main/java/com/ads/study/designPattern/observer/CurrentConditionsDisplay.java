package com.ads.study.designPattern.observer;

import com.ads.study.designPattern.observer.ObserverInterface.DisplayElement;
import com.ads.study.designPattern.observer.ObserverInterface.Observer;
import com.ads.study.designPattern.observer.ObserverInterface.Subject;

import java.io.ObjectOutputStream;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-06-08
 * Time: 18:31
 */
public class CurrentConditionsDisplay implements Observer,DisplayElement{

    private String humidity;

    private Subject subject;

    public CurrentConditionsDisplay(Subject subject){
        this.subject=subject;
        subject.registerObserver(this);
    }

    @Override
    public void display() {
        System.out.println(humidity);
    }

    @Override
    public void update(String humidity) {
        this.humidity=humidity;
        display();
    }
}
