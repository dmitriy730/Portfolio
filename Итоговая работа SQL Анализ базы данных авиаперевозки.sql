== ИТОГОВАЯ РАБОТА - АНАЛИЗ БАЗЫ ДАННЫХ АВИАПЕРЕВОЗКИ 

--1.Выведите название самолетов, которые имеют менее 50 посадочных мест?

select a.aircraft_code, a.model, count(s.seat_no) 
from aircrafts a
join seats s on a.aircraft_code = s.aircraft_code 
group by a.aircraft_code 
having count(s.seat_no) < 50


--2.Выведите процентное изменение ежемесячной суммы бронирования билетов, округленной до сотых.

select date_trunc('month', book_date), sum(total_amount),
 round(((sum(total_amount) - lag(sum(total_amount), 1) over (order by date_trunc('month', book_date))) / lag(sum(total_amount), 1) over (order by date_trunc('month', book_date))) * 100, 2) as "%"
from bookings b
group by 1 
order by 1


--3. Выведите названия самолетов не имеющих бизнес - класс. Решение должно быть через функцию array_agg


select a.model, t.klass
from (
	select aircraft_code, array_agg(fare_conditions) klass
	from seats s 
	group by 1) t
join aircrafts a on a.aircraft_code = t.aircraft_code
where not 'Business' = any(t.klass)


--4. Вывести накопительный итог количества мест в самолетах по каждому аэропорту на каждый день, 
--учитывая только те самолеты, которые летали пустыми 
--и только те дни, где из одного аэропорта таких самолетов вылетало более одного.
--В результате должны быть код аэропорта, дата, количество пустых мест и накопительный итог.


select departure_airport, date, sum, 
sum(sum) over (partition by departure_airport order by date) as sum_all
from
(select departure_airport, date, sum(count_m) as sum
from
(select departure_airport, date, count*count_s as count_m
from
(select actual_departure::date as date, departure_airport, aircraft_code, count(aircraft_code)
from
(select f.flight_id, f.actual_departure::date, f.departure_airport, f.aircraft_code, count(bp.boarding_no)
from flights f
left join boarding_passes bp using(flight_id)
where f.actual_departure is not null
group by f.flight_id, f.actual_departure::date, f.departure_airport
having count(bp.boarding_no) = 0
order by f.actual_departure::date, f.departure_airport)t1
group by actual_departure::date, departure_airport, aircraft_code
having count(aircraft_code) > 1)t2
left join
(select aircraft_code, count(seat_no) as count_s
from seats 
group by aircraft_code) s using(aircraft_code))t3
group by departure_airport, date
order by departure_airport)t4 

		
	
--5. Найдите процентное соотношение перелетов по маршрутам от общего количества перелетов. 
--Выведите в результат названия аэропортов и процентное отношение.Решение должно быть через оконную функцию.


with cte as (
	select flight_id, flight_no, departure_airport_name, arrival_airport_name, 
	count(flight_id) over (partition by flight_no), 
	round(count(flight_id) over(partition by flight_no)::numeric / count(flight_id) over () * 100, 2) as "%"	
	from flights_v 
	group by flight_id, flight_no, departure_airport_name, arrival_airport_name)
select distinct(departure_airport_name), arrival_airport_name, "%"
from cte
order by "%" desc


--6. Выведите количество пассажиров по каждому коду сотового оператора, если учесть, что код оператора 
--- это три символа после +7

select distinct(cod), count(passenger_id) over(partition by cod) "Количество пассажиров"
from (
	select passenger_id, contact_data ->> 'phone', substring(contact_data ->> 'phone' from 3 for 3) cod
	from tickets) t
group by cod, passenger_id 


	
--7. Классифицируйте финансовые обороты (сумма стоимости билетов) по маршрутам:
--До 50 млн - low
--От 50 млн включительно до 150 млн - middle
--От 150 млн включительно - high
--Выведите в результат количество маршрутов в каждом полученном классе.

select distinct(t.case) as "Маршруты", count(t.sum) as "Количество"
from (
	select f.flight_no, sum(tf.amount),
		case when sum(amount) < 50000000 then 'low'
			 when sum(amount) >= 150000000 then 'high'
			else 'middle'	
			end 
	from flights f 
	join ticket_flights tf on f.flight_id = tf.flight_id 
	group by flight_no) t
group by 1


--8. Вычислите медиану стоимости билетов, медиану размера бронирования и отношение медианы бронирования 
--к медиане стоимости билетов, округленной до сотых.


select percentile_cont(0.5) within group (order by t1.am_t) as "Median ticket", 
percentile_cont(0.5) within group (order by b2.total_amount) as "Median bookings",
round(percentile_cont(0.5) within group (order by b2.total_amount)::numeric / percentile_cont(0.5) 
within group (order by t1.am_t)::numeric, 2) as "Отношение"
from
(select f.scheduled_departure::date date, tf.amount am_t, tf.ticket_no 
from flights f 
join ticket_flights tf using(flight_id)
order by 1)t1
join tickets t using(ticket_no)
join bookings b2 using(book_ref)



--9. Найдите значение минимальной стоимости полета 1 км для пассажиров. То есть нужно найти расстояние между аэропортами и с учетом стоимости билетов получить искомый результат.

create extension if not exists earthdistance cascade 


 with cte1 as ( 
	select a.airport_code a_cod, a.airport_name A, b.airport_code b_cod, b.airport_name B, 
			earth_distance(ll_to_earth(a.latitude, a.longitude), ll_to_earth(b.latitude, b.longitude)) / 1000 as distance  
	from airports a, airports b 
	where a.airport_name != b.airport_name), 
cte2 as (
	select f.departure_airport d_port, f.arrival_airport a_port, tf.amount price  
	from flights f 
	join ticket_flights tf on f.flight_id = tf.flight_id 
	group by f.departure_airport, f.arrival_airport, tf.amount
	order by tf.amount) 
select cte1.a_cod, cte1.b_cod, cte1.distance, cte2.price, cte2.price / cte1.distance price_km
from cte1
join cte2 on cte1.a_cod = cte2.d_port and cte1.b_cod = cte2.a_port
group by cte1.a_cod, cte1.b_cod, cte1.distance, cte2.price
order by cte2.price / cte1.distance
limit 1