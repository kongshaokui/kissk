package com.ads.study.designPattern;

import com.ads.study.designPattern.observer.CurrentConditionsDisplay;
import com.ads.study.designPattern.observer.WeatherData;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-05-22
 * Time: 16:56
 */
public class Study {

    public static void main(String[] args) {

        WeatherData weatherData = new WeatherData();
        CurrentConditionsDisplay currentConditionsDisplay = new CurrentConditionsDisplay(weatherData);
        weatherData.setMeasurements("天气");
        weatherData.setMeasurements("阴天");
    }

}
