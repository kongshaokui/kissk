package com.ads.study.Event;

import java.util.EventListener;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-09-14
 * Time: 14:50
 */
public interface DoorListener extends EventListener{

    void doorEvent(DoorEvent doorEvent);

}
