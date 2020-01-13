package com.ads.study.designFactory;

/**
 * @Classname ToyFactory
 * @Description TODO
 * @Created by kongshaokui
 * @Date 2019/9/24 16:33
 */
public class ToyFactory {

    private static ToyInterface  getToy(String toyName){

        ToyInterface toy = null;

        switch (toyName){
            case "duck":
                toy = new Duck();
                break;
            case "chick":
                toy = new Chick();
                break;
            case "car":
                toy = new Car();
                break;
            default:
                break;
        }

        return toy;
    }

    public static void main(String[] args) {

        ToyInterface carFactory = new CarFactory().newToy();
        System.out.println(carFactory.cry());
        ToyInterface duckFactory = new DuckFactory().newToy();
        System.out.println(duckFactory.cry());
        ToyInterface chickFactory = new ChickFactory().newToy();
        System.out.println(chickFactory.cry());

        ToyInterface duck = ToyFactory.getToy("duck");
        ToyInterface chick = ToyFactory.getToy("chick");
        ToyInterface car = ToyFactory.getToy("car");
        System.out.println(duck.cry());
        System.out.println(chick.cry());
        System.out.println(car.cry());
    }

}
