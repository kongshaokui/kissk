package com.ads.study.designPattern.observer;

import com.ads.study.designPattern.observer.ObserverInterface.Observer;
import com.ads.study.designPattern.observer.ObserverInterface.Subject;

import java.util.ArrayList;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-06-08
 * Time: 16:50
 */
public class WeatherData implements Subject {

    private ArrayList<Observer> observers;

    public WeatherData(){
        observers=new ArrayList<Observer>();
    }

    /**
     * 观察数据
     */
    private String humidity;

    @Override
    public void registerObserver(Observer o) {
        observers.add(o);
    }

    @Override
    public void removeObserver(Observer o) {
        int i = observers.indexOf(o);
        if (i >= 0) {
            observers.remove(i);
        }

    }

    @Override
    public void notifyObservers() {
        for (Observer o : observers) {
            o.update(humidity);
        }
    }

    public void measuermentsChange() {
        notifyObservers();
    }

    public void setMeasurements(String humidity) {
        this.humidity = humidity;
        measuermentsChange();
    }

}
