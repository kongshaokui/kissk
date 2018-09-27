package com.ads.study.Event;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-09-14
 * Time: 16:21
 */
public class EventTest {

    public static void main(String[] args){
        Door door = new Door();
        door.register(new DoorListenerImpl());
        door.openDoor();
        System.out.println("--------------------");
        door.closeDoor();
    }
}
